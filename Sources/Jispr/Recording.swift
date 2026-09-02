import AVFoundation
import Foundation
import JisprCore

/// What a double tap of Right Option starts.
enum Mode: String, CaseIterable {
    case dictate
    case record

    var title: String {
        switch self {
        case .dictate: return "Dictate (paste text)"
        case .record: return "Record to file"
        }
    }

    var hint: String {
        switch self {
        case .dictate: return "Double-tap Right ⌥ to dictate · tap ⌥ to paste · Esc to abort"
        case .record: return "Double-tap Right ⌥ to record · tap ⌥ to save · Esc to abort"
        }
    }

    private static let defaultsKey = "mode"

    static var selected: Mode {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(Mode.init(rawValue:)) ?? .dictate
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Writes microphone buffers to an AAC file (.m4a) while a recording runs.
final class RecordingWriter: AudioSink {
    static let fileExtension = "m4a"

    let url: URL
    private let sampleRate: Double
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var writeError: Error?

    /// Creates the file at `url`. Buffers must come in `format` (the microphone format).
    init(url: URL, format: AVAudioFormat) throws {
        self.url = url
        self.sampleRate = format.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(
            forWriting: url, settings: settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, writeError == nil else { return }
        do {
            try file.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            writeError = error
            Log.audio.error("Recording write failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Finalizes the file. Returns the recorded length in seconds.
    func close() throws -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        if let file {
            file.close()
            self.file = nil
        }
        if let writeError { throw writeError }
        return Double(frames) / sampleRate
    }

    /// Closes the file and deletes it.
    func discard() {
        _ = try? close()
        try? FileManager.default.removeItem(at: url)
    }
}

/// Where recordings and transcripts go.
enum Recordings {
    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// A temporary file the recording is written to until it is saved.
    static func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jispr-recording-\(UUID().uuidString)")
            .appendingPathExtension(RecordingWriter.fileExtension)
    }

    /// `<dir>/<base>.<ext>`, with `-2`, `-3`, ... added when the name is taken.
    static func freeURL(in dir: URL, base: String, ext: String) -> URL {
        let name = FileNaming.unique(base: base, ext: ext) { candidate in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path)
        }
        return dir.appendingPathComponent(name)
    }
}
