import AppKit
import Foundation

/// State machine: idle -> preparing -> listening -> finishing -> idle.
///
/// Keys:
/// - double-tap Right Option: start
/// - single tap Right Option while running: stop and paste
/// - Escape while running: abort, nothing is pasted
@MainActor
final class DictationController {
    enum State: Equatable { case idle, preparing, listening, finishing }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?

    private var engine: SpeechEngine
    private let audio = AudioCapture()
    private let indicator = IndicatorPanel()
    private var startTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    init() {
        engine = EngineKind.selected.makeEngine()
        audio.onLevel = { [weak self] level in self?.indicator.update(level: level) }
        Log.app.info("Engine: \(self.engine.kind.rawValue, privacy: .public)")
        Task { await engine.prewarm() }
    }

    /// Double tap of right Option: start when idle.
    func handleDoubleTap() {
        if state == .idle { start() }
    }

    /// Single tap of right Option. Returns true when Jispr used the tap.
    func handleOptionTap() -> Bool {
        switch state {
        case .idle: return false
        case .listening: finish(); return true
        case .preparing, .finishing: return true
        }
    }

    /// Escape: abort without pasting. Returns true when the key must not reach the front app.
    func handleEscape() -> Bool {
        switch state {
        case .listening, .preparing: abort(); return true
        case .idle, .finishing: return false
        }
    }

    /// The user picked another engine in the menu. Applied now when idle, else at the next start.
    func engineSelectionChanged() {
        guard state == .idle else { return }
        switchEngineIfNeeded()
    }

    // MARK: - Private

    private func switchEngineIfNeeded() {
        let wanted = EngineKind.selected
        guard wanted != engine.kind else { return }
        let old = engine
        Task { await old.cancel() }
        engine = wanted.makeEngine()
        Log.app.info("Engine switched to \(wanted.rawValue, privacy: .public)")
        Task { await engine.prewarm() }
    }

    private func start() {
        guard startTask == nil else { return }
        errorTask?.cancel()
        switchEngineIfNeeded()
        state = .preparing
        indicator.show(.preparing(progress: nil))
        Log.app.info("Dictation starting")

        startTask = Task { [self] in
            defer { startTask = nil }
            do {
                guard await Permissions.requestMicrophone() else { throw JisprError.microphoneDenied }
                try Task.checkCancellation()
                let sink = try await engine.start { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.state == .preparing else { return }
                        // Past the download, the model is being loaded: no number to show.
                        self.indicator.model.phase = .preparing(progress: progress < 0.999 ? progress : nil)
                    }
                }
                try Task.checkCancellation()
                let stream = try audio.start()
                feedTask = Task.detached(priority: .userInitiated) {
                    for await buffer in stream { sink.feed(buffer) }
                }
                state = .listening
                indicator.model.phase = .listening
                Log.app.info("Dictation listening")
            } catch is CancellationError {
                await engine.cancel()
                await engine.prewarm()
            } catch {
                Log.app.error("Dictation failed to start: \(String(describing: error), privacy: .public)")
                await engine.cancel()
                audio.stop()
                state = .idle
                showError(error.localizedDescription)
            }
        }
    }

    /// Stop listening, finalize, paste.
    private func finish() {
        guard state == .listening else { return }
        state = .finishing
        indicator.model.phase = .finishing
        audio.stop()
        Log.app.info("Dictation finishing")

        Task { [self] in
            await feedTask?.value
            feedTask = nil
            var text = ""
            do {
                text = try await engine.finish()
            } catch {
                Log.app.error("Finalize failed: \(String(describing: error), privacy: .public)")
            }
            indicator.hide()
            state = .idle
            if text.isEmpty {
                Log.app.info("Nothing transcribed")
            } else {
                await TextInserter.insert(text)
            }
            Task { await engine.prewarm() }
        }
    }

    /// Stop listening and throw the audio away. Nothing is pasted.
    private func abort() {
        Log.app.info("Dictation aborted")
        let wasStarting = startTask != nil
        startTask?.cancel()
        audio.stop()
        feedTask?.cancel()
        feedTask = nil
        indicator.hide()
        state = .idle
        if !wasStarting {
            // Already listening: the start task is gone, so clean up here.
            Task { [self] in
                await engine.cancel()
                await engine.prewarm()
            }
        }
    }

    private func showError(_ message: String) {
        indicator.show(.error(message))
        errorTask = Task { [self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, state == .idle else { return }
            indicator.hide()
        }
    }
}
