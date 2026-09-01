import AVFoundation
import Foundation
import Speech

/// Thread-safe sink that converts buffers and feeds them to a running analyzer.
final class AnalyzerFeeder: AudioSink {
    private let builder: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let converter = BufferConverter()

    init(builder: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) {
        self.builder = builder
        self.format = format
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        do {
            let converted = try converter.convert(buffer, to: format)
            builder.yield(AnalyzerInput(buffer: converted))
        } catch {
            Log.speech.error("Buffer conversion failed: \(String(describing: error), privacy: .public)")
        }
    }

    func finish() { builder.finish() }
}

/// Apple's on-device SpeechAnalyzer (macOS 26). Streams audio in and finalizes at the end.
@MainActor
final class AppleSpeechEngine: SpeechEngine {
    let kind: EngineKind = .apple
    static let locale = Locale(identifier: "en-US")

    enum Failure: LocalizedError {
        case notAvailable
        case localeNotSupported
        case noAudioFormat
        case notStarted

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "On-device speech recognition is not available on this Mac"
            case .localeNotSupported: return "English (US) speech model is not supported"
            case .noAudioFormat: return "No compatible audio format for the speech model"
            case .notStarted: return "Transcription was not started"
            }
        }
    }

    private struct Prepared {
        let module: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat
    }

    private var prepareTask: Task<Prepared, Error>?
    private var analyzer: SpeechAnalyzer?
    private var feeder: AnalyzerFeeder?
    private var resultsTask: Task<String, Error>?

    var isRunning: Bool { analyzer != nil }

    // MARK: Model

    static func modelStatus() async -> AssetInventory.Status {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        return await AssetInventory.status(forModules: [module])
    }

    /// Loads the model in the background. Only when it is already installed (no silent download).
    func prewarm() async {
        guard prepareTask == nil, analyzer == nil else { return }
        guard await Self.modelStatus() == .installed else { return }
        prepareTask = Task { try await Self.prepare(onProgress: nil) }
    }

    private static func prepare(onProgress: ModelProgressHandler?) async throws -> Prepared {
        guard SpeechTranscriber.isAvailable else { throw Failure.notAvailable }
        let module = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await ensureModel(for: module, onProgress: onProgress)
        let analyzer = SpeechAnalyzer(modules: [module])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        Log.speech.info("Analyzer prepared (\(format.sampleRate, privacy: .public) Hz)")
        return Prepared(module: module, analyzer: analyzer, format: format)
    }

    private static func ensureModel(for module: SpeechTranscriber, onProgress: ModelProgressHandler?) async throws {
        let wanted = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == wanted }) else {
            throw Failure.localeNotSupported
        }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == wanted }) { return }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        Log.speech.info("Downloading speech model for \(wanted, privacy: .public)")
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
            onProgress?(progress.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        Log.speech.info("Speech model installed")
    }

    // MARK: Session

    /// Starts a session. Returns the feeder to push microphone buffers into.
    func start(onModelProgress: ModelProgressHandler?) async throws -> AudioSink {
        if analyzer != nil { await cancel() }

        let task = prepareTask ?? Task { try await Self.prepare(onProgress: onModelProgress) }
        prepareTask = nil
        let prepared = try await task.value

        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        let module = prepared.module
        resultsTask = Task {
            var finalized = ""
            var volatile = ""
            for try await result in module.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalized += text
                    volatile = ""
                } else {
                    volatile = text
                }
            }
            return finalized + volatile
        }

        try await prepared.analyzer.start(inputSequence: stream)
        analyzer = prepared.analyzer
        let feeder = AnalyzerFeeder(builder: builder, format: prepared.format)
        self.feeder = feeder
        Log.speech.info("Session started")
        return feeder
    }

    /// Ends the session and returns the final text.
    func finish() async throws -> String {
        guard let analyzer, let resultsTask else { throw Failure.notStarted }
        feeder?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let raw = try await resultsTask.value
        reset()
        let text = TextTidy.tidy(raw)
        Log.speech.info("Session finished: \(text.count, privacy: .public) chars")
        return text
    }

    func cancel() async {
        feeder?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        reset()
        Log.speech.info("Session cancelled")
    }

    private func reset() {
        analyzer = nil
        feeder = nil
        resultsTask = nil
    }

}
