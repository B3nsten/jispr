import AVFoundation
import Foundation
import JisprCore

/// Writes microphone buffers to lossless chunks (ALAC in .m4a) of a few minutes each, so a crash
/// loses little: an m4a is readable only once it is closed. `close()` returns the chunks;
/// `RecordingJoiner` encodes them once into one AAC file. Buffers in another format (the
/// microphone changed) are converted.
final class RecordingWriter: AudioSink {
    static let fileExtension = "m4a"
    /// Length of one chunk. A crash loses at most this much.
    static let chunkSeconds: Double = 300

    /// The saved file: AAC, small enough for hours.
    static func aacSettings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// The chunks: Apple Lossless, so the final encode is the only lossy step.
    static func chunkSettings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 16,
        ]
    }

    let directory: URL
    private let format: AVAudioFormat
    private let converter = BufferConverter()
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var chunks: [URL] = []
    private var chunkFrames: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var writeError: Error?

    /// Makes `directory` and the first chunk in it. Buffers should come in `format` (the microphone format).
    init(directory: URL, format: AVAudioFormat) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        self.format = format
        file = try openChunk()
    }

    private func openChunk() throws -> AVAudioFile {
        let url = directory
            .appendingPathComponent(String(format: "chunk-%04d", chunks.count + 1))
            .appendingPathExtension(Self.fileExtension)
        let file = try AVAudioFile(
            forWriting: url, settings: Self.chunkSettings(for: format),
            commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
        chunks.append(url)
        chunkFrames = 0
        return file
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, writeError == nil else { return }
        do {
            let converted = try converter.convert(buffer, to: format)
            if Double(chunkFrames) >= Self.chunkSeconds * format.sampleRate {
                file.close()
                self.file = try openChunk()
                Log.audio.info("Recording chunk \(self.chunks.count, privacy: .public) started")
            }
            try self.file?.write(from: converted)
            chunkFrames += AVAudioFramePosition(converted.frameLength)
            totalFrames += AVAudioFramePosition(converted.frameLength)
        } catch {
            writeError = error
            Log.audio.error("Recording write failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Finalizes the current chunk. Returns all chunks in order and the recorded length in seconds.
    func close() throws -> (chunks: [URL], seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if let file {
            file.close()
            self.file = nil
        }
        if let writeError { throw writeError }
        return (chunks, Double(totalFrames) / format.sampleRate)
    }

    /// Closes the current chunk and deletes everything.
    func discard() {
        _ = try? close()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Makes one AAC file of the lossless chunks: decoded in order, encoded once.
enum RecordingJoiner {
    enum Failure: LocalizedError {
        case noChunks
        var errorDescription: String? { "The recording has no audio" }
    }

    /// Writes `output` (which must not exist yet) from the chunks, in order.
    static func join(_ chunks: [URL], to output: URL) async throws {
        guard let first = chunks.first else { throw Failure.noChunks }
        try await Task.detached(priority: .userInitiated) {
            let format = try AVAudioFile(forReading: first).processingFormat
            let out = try AVAudioFile(
                forWriting: output, settings: RecordingWriter.aacSettings(for: format),
                commonFormat: format.commonFormat, interleaved: format.isInterleaved
            )
            let converter = BufferConverter()
            let frames: AVAudioFrameCount = 32_768
            for chunk in chunks {
                let file = try AVAudioFile(forReading: chunk)
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
                    try file.read(into: buffer, frameCount: frames)
                    if buffer.frameLength == 0 { break }
                    try out.write(from: converter.convert(buffer, to: format))
                }
            }
            out.close()
        }.value
        Log.audio.info("Encoded \(chunks.count, privacy: .public) chunks into \(output.lastPathComponent, privacy: .public)")
    }
}

/// Chunk folders left behind by a crash. Joined and saved to Downloads at the next launch.
enum RecordingRecovery {
    /// One folder per recording, named by the start time in seconds since 1970.
    static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Jispr/recordings")
    }

    static func directory(startingAt date: Date) -> URL {
        root.appendingPathComponent(String(Int(date.timeIntervalSince1970)))
    }

    /// Saves every left-over recording as `meeting_…-recovered.m4a` in Downloads and removes its folder.
    /// The chunk that was being written at the crash is unreadable and skipped. Returns the saved files.
    static func recover() async -> [URL] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var saved: [URL] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let chunks = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == RecordingWriter.fileExtension }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .filter { (try? AVAudioFile(forReading: $0)) != nil }
            guard let last = chunks.last else {
                Log.audio.warning("Recording folder \(folder.lastPathComponent, privacy: .public) has no readable audio; removed")
                try? fm.removeItem(at: folder)
                continue
            }
            // The last good chunk was closed when the next one started: that is the end of what we have.
            let end = (try? last.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let output = Recordings.freeURL(
                in: Recordings.downloads,
                base: FileNaming.meetingName(at: end) + "-recovered", ext: RecordingWriter.fileExtension
            )
            do {
                try await RecordingJoiner.join(chunks, to: output)
                try? fm.removeItem(at: folder)
                saved.append(output)
                Log.audio.info("Recovered \(output.path, privacy: .public)")
            } catch {
                Log.audio.error("Recovery of \(folder.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        return saved
    }
}
