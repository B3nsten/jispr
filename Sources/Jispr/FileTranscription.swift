import AVFoundation
import Foundation

/// Developer helper: `Jispr --transcribe <audio file> [parakeet|apple]` prints the transcript.
enum FileTranscription {
    static func run(path: String, engineName: String?) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            let kind = engineName.flatMap(EngineKind.init(rawValue:)) ?? EngineKind.selected
            FileHandle.standardError.write(Data("engine: \(kind.rawValue)\n".utf8))
            let engine = await kind.makeEngine()
            let lastPercent = LockedValue(-1)
            let feeder = try await engine.start { progress in
                let percent = Int(progress * 100)
                guard lastPercent.swap(percent) != percent else { return }
                FileHandle.standardError.write(Data("model download \(percent)%\n".utf8))
            }
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let chunk: AVAudioFrameCount = 8192
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                try file.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { break }
                feeder.feed(buffer)
            }
            let text = try await engine.finish()
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
