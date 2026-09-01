import AVFoundation
import Foundation

/// Receives microphone buffers during a session. Called from the audio feed task.
protocol AudioSink: AnyObject {
    func feed(_ buffer: AVAudioPCMBuffer)
}

/// Model download progress, 0...1.
typealias ModelProgressHandler = @Sendable (Double) -> Void

/// A speech-to-text backend. One session at a time.
@MainActor
protocol SpeechEngine: AnyObject {
    var kind: EngineKind { get }
    /// Load the model in the background so the first dictation starts fast.
    func prewarm() async
    /// Begin a session. Returns the sink to push audio into.
    func start(onModelProgress: ModelProgressHandler?) async throws -> AudioSink
    /// End the session and return the text.
    func finish() async throws -> String
    /// Drop the session. Nothing is returned.
    func cancel() async
}

enum EngineKind: String, CaseIterable {
    case parakeet
    case apple

    var title: String {
        switch self {
        case .parakeet: return "Parakeet (NVIDIA, on-device)"
        case .apple: return "Apple Speech"
        }
    }

    private static let defaultsKey = "engine"

    static var selected: EngineKind {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(EngineKind.init(rawValue:)) ?? .parakeet
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    @MainActor
    func makeEngine() -> SpeechEngine {
        switch self {
        case .parakeet: return ParakeetEngine()
        case .apple: return AppleSpeechEngine()
        }
    }
}

enum TextTidy {
    static func tidy(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([.,!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
