import AppKit
import Foundation

/// State machine: idle -> preparing -> listening -> finishing -> idle.
@MainActor
final class DictationController {
    enum State: Equatable { case idle, preparing, listening, finishing }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?

    private let transcriber = Transcriber()
    private let audio = AudioCapture()
    private let indicator = IndicatorPanel()
    private var startTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    init() {
        audio.onLevel = { [weak self] level in self?.indicator.update(level: level) }
        Task { await transcriber.prewarmIfInstalled() }
    }

    /// Double tap of right Option: start when idle, finish when listening.
    func toggle() {
        switch state {
        case .idle: start()
        case .listening: finish()
        case .preparing, .finishing: break
        }
    }

    /// Escape. Returns true when Jispr used the key (and it must not reach the front app).
    func handleEscape() -> Bool {
        switch state {
        case .listening: finish(); return true
        case .preparing: cancel(); return true
        case .idle, .finishing: return false
        }
    }

    // MARK: - Private

    private func start() {
        guard startTask == nil else { return }
        errorTask?.cancel()
        state = .preparing
        indicator.show(.preparing(progress: nil))
        Log.app.info("Dictation starting")

        startTask = Task { [self] in
            defer { startTask = nil }
            do {
                guard await Permissions.requestMicrophone() else { throw JisprError.microphoneDenied }
                try Task.checkCancellation()
                let feeder = try await transcriber.start { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.state == .preparing else { return }
                        self.indicator.model.phase = .preparing(progress: progress)
                    }
                }
                try Task.checkCancellation()
                let stream = try audio.start()
                feedTask = Task.detached(priority: .userInitiated) {
                    for await buffer in stream { feeder.feed(buffer) }
                }
                state = .listening
                indicator.model.phase = .listening
                Log.app.info("Dictation listening")
            } catch is CancellationError {
                await transcriber.cancel()
            } catch {
                Log.app.error("Dictation failed to start: \(String(describing: error), privacy: .public)")
                await transcriber.cancel()
                audio.stop()
                state = .idle
                showError(error.localizedDescription)
            }
        }
    }

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
                text = try await transcriber.finish()
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
            Task { await transcriber.prewarmIfInstalled() }
        }
    }

    private func cancel() {
        Log.app.info("Dictation cancelled")
        startTask?.cancel()
        audio.stop()
        feedTask?.cancel()
        feedTask = nil
        indicator.hide()
        state = .idle
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
