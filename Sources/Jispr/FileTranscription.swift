import AVFoundation
import Foundation

/// Transcribes whole audio files.
enum FileTranscription {
    /// Feeds the audio file into the engine and returns the text.
    /// With Parakeet, the file goes through v3 (25 languages, detected automatically) and the
    /// text is split by speaker (`[14:02:05] Person 1: …`) when more than one is heard. The clock
    /// times come from the `meeting_…` file name; other files get times from the start of the file.
    @MainActor
    static func transcribe(
        _ url: URL, with engine: SpeechEngine, onModelProgress: ModelProgressHandler? = nil
    ) async throws -> String {
        let sink = try await engine.start(onModelProgress: onModelProgress)
        do {
            try await Task.detached(priority: .userInitiated) { try feed(url, into: sink) }.value
        } catch {
            await engine.cancel()
            throw error
        }
        if let parakeet = engine as? ParakeetEngine {
            return try await parakeet.finishFile(savedAt: Recordings.savedTime(of: url), onModelProgress: onModelProgress)
        }
        return try await engine.finish()
    }

    /// Reads the file in chunks and pushes them into the sink.
    private static func feed(_ url: URL, into sink: AudioSink) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 8192
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            sink.feed(buffer)
        }
    }

    /// Developer helper: `Jispr --transcribe <audio file> [parakeet|apple]` prints the transcript.
    static func run(path: String, engineName: String?) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            let kind = engineName.flatMap(EngineKind.init(rawValue:)) ?? EngineKind.selected
            FileHandle.standardError.write(Data("engine: \(kind.rawValue)\n".utf8))
            let engine = await kind.makeEngine()
            let lastPercent = LockedValue(-1)
            let text = try await transcribe(url, with: engine) { progress in
                let percent = Int(progress * 100)
                guard lastPercent.swap(percent) != percent else { return }
                FileHandle.standardError.write(Data("model download \(percent)%\n".utf8))
            }
            print(text)
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}

/// Tiny thread-safe box for a value.
final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }

    /// Stores the new value and returns the old one.
    func swap(_ new: T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
}
