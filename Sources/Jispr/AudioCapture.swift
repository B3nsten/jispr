import AVFoundation
import Foundation

/// Microphone capture. Yields PCM buffers into an AsyncStream and reports a 0...1 level.
final class AudioCapture {
    enum Failure: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input available" }
    }

    /// Called on the main actor with a smoothed level in 0...1.
    var onLevel: (@MainActor (Float) -> Void)?

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var isRunning = false

    /// The format the microphone delivers. Buffers from `start()` come in this format.
    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw Failure.noInput }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.continuation?.yield(buffer)
            if let onLevel = self.onLevel {
                let level = Self.level(of: buffer)
                Task { @MainActor in onLevel(level) }
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        Log.audio.info("Capture started: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
        return stream
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
        Log.audio.info("Capture stopped")
    }

    /// RMS mapped from roughly -50 dB...-10 dB onto 0...1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(n))
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 50) / 40))
    }
}
