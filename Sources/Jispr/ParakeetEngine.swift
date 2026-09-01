import AVFoundation
import FluidAudio
import Foundation
import JisprCore

/// Collects 16 kHz mono samples while a session runs.
final class SampleAccumulator: AudioSink {
    private let converter = BufferConverter()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!
    private let lock = NSLock()
    private var samples: [Float] = []

    func feed(_ buffer: AVAudioPCMBuffer) {
        do {
            let converted = try converter.convert(buffer, to: format)
            guard let channel = converted.floatChannelData?[0] else { return }
            let count = Int(converted.frameLength)
            lock.lock()
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            lock.unlock()
        } catch {
            Log.speech.error("Buffer conversion failed: \(String(describing: error), privacy: .public)")
        }
    }

    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let out = samples
        samples = []
        return out
    }
}

/// Passes download progress from a background load task to whoever listens right now.
final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ModelProgressHandler?

    func set(_ handler: ModelProgressHandler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func report(_ value: Double) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(value)
    }
}

/// NVIDIA Parakeet TDT 0.6B v2 (English). CoreML build from Hugging Face, run by FluidAudio.
/// Audio is collected during the session and transcribed in one go at the end.
@MainActor
final class ParakeetEngine: SpeechEngine {
    let kind: EngineKind = .parakeet

    enum Failure: LocalizedError {
        case notStarted
        var errorDescription: String? { "Transcription was not started" }
    }

    private let progress = ProgressRelay()
    private var loadTask: Task<AsrManager, Error>?
    private var manager: AsrManager?
    private var accumulator: SampleAccumulator?

    func prewarm() async {
        guard manager == nil, loadTask == nil else { return }
        loadTask = Task { try await Self.load(progress: progress) }
    }

    private static func load(progress: ProgressRelay) async throws -> AsrManager {
        Log.speech.info("Loading Parakeet v2 model")
        let models = try await AsrModels.downloadAndLoad(version: .v2) { update in
            progress.report(update.fractionCompleted)
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        Log.speech.info("Parakeet ready")
        return manager
    }

    func start(onModelProgress: ModelProgressHandler?) async throws -> AudioSink {
        if manager == nil {
            progress.set(onModelProgress)
            defer { progress.set(nil) }
            let task = loadTask ?? Task { try await Self.load(progress: progress) }
            loadTask = nil
            manager = try await task.value
        }
        let accumulator = SampleAccumulator()
        self.accumulator = accumulator
        Log.speech.info("Session started (Parakeet)")
        return accumulator
    }

    func finish() async throws -> String {
        guard let manager, let accumulator else { throw Failure.notStarted }
        self.accumulator = nil
        let samples = accumulator.drain()
        let seconds = Double(samples.count) / 16_000
        guard seconds >= 0.3 else { return "" }

        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &state)
        let text = TextCleanup.clean(result.text, normalizeAllCaps: true, keepCaps: Settings.keepCaps)
        let took = Date().timeIntervalSince(started)
        Log.speech.info("Parakeet: \(seconds, format: .fixed(precision: 1), privacy: .public) s audio in \(took, format: .fixed(precision: 2), privacy: .public) s, \(text.count, privacy: .public) chars")
        return text
    }

    func cancel() async {
        accumulator = nil
    }
}
