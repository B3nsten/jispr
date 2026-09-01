import AVFoundation
import Foundation

/// Developer helper: `Jispr --transcribe <audio file>` prints the transcript.
enum FileTranscription {
    static func run(path: String) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            let transcriber = await Transcriber()
            let feeder = try await transcriber.start { progress in
                FileHandle.standardError.write(Data("model download \(Int(progress * 100))%\n".utf8))
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
            let text = try await transcriber.finish()
            print(text)
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}
