import AppKit
import Foundation
import JisprCore

/// State machine: idle -> preparing -> listening | recording -> finishing -> idle.
///
/// Keys (see `Mode`):
/// - double-tap Right Option: start dictating, or start recording to a file
/// - single tap Right Option while running: stop; paste the text, or save the file
/// - Escape while running: abort, nothing is pasted or saved
///
/// The menu can also transcribe an audio file (`transcribing`). Keys are ignored meanwhile.
@MainActor
final class DictationController {
    enum State: Equatable { case idle, preparing, listening, recording, finishing, transcribing }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?

    private var engine: SpeechEngine
    private let audio = AudioCapture()
    private let indicator = IndicatorPanel()
    private var startTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var recording: RecordingWriter?

    init() {
        engine = EngineKind.selected.makeEngine()
        audio.onLevel = { [weak self] level in self?.indicator.update(level: level) }
        Log.app.info("Engine: \(self.engine.kind.rawValue, privacy: .public)")
        Task { await engine.prewarm() }
    }

    /// Double tap of right Option: start when idle. What starts depends on the mode.
    func handleDoubleTap() {
        guard state == .idle else { return }
        switch Mode.selected {
        case .dictate: startDictation()
        case .record: startRecording()
        }
    }

    /// Single tap of right Option. Returns true when Jispr used the tap.
    func handleOptionTap() -> Bool {
        switch state {
        case .idle, .transcribing: return false
        case .listening: finishDictation(); return true
        case .recording: finishRecording(); return true
        case .preparing, .finishing: return true
        }
    }

    /// Escape: abort without pasting or saving. Returns true when the key must not reach the front app.
    func handleEscape() -> Bool {
        switch state {
        case .listening, .recording, .preparing: abort(); return true
        case .idle, .finishing, .transcribing: return false
        }
    }

    /// The user picked another engine in the menu. Applied now when idle, else at the next start.
    func engineSelectionChanged() {
        guard state == .idle else { return }
        switchEngineIfNeeded()
    }

    /// Menu: transcribe an audio file. The text is saved as `.txt` next to it.
    func transcribeFile(_ url: URL) {
        guard state == .idle else { return }
        noticeTask?.cancel()
        switchEngineIfNeeded()
        state = .transcribing
        let name = url.lastPathComponent
        indicator.show(.transcribing(name))
        Log.app.info("Transcribing \(url.path, privacy: .public)")

        Task { [self] in
            do {
                let text = try await FileTranscription.transcribe(url, with: engine) { progress in
                    Task { @MainActor in
                        guard self.state == .transcribing else { return }
                        self.indicator.model.phase = progress < 0.999 ? .preparing(progress: progress) : .transcribing(name)
                    }
                }
                state = .idle
                if text.isEmpty {
                    Log.app.info("Nothing transcribed")
                    showNotice(.error("Nothing transcribed"))
                } else {
                    let out = Recordings.freeURL(
                        in: url.deletingLastPathComponent(),
                        base: url.deletingPathExtension().lastPathComponent, ext: "txt"
                    )
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    Log.app.info("Saved \(out.path, privacy: .public)")
                    showNotice(.saved(out.lastPathComponent))
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                }
            } catch {
                Log.app.error("Transcribing failed: \(String(describing: error), privacy: .public)")
                state = .idle
                showNotice(.error(error.localizedDescription))
            }
            Task { await engine.prewarm() }
        }
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

    /// Starts the microphone and pumps its buffers into the sink.
    private func startCapture(into sink: AudioSink) throws {
        let stream = try audio.start()
        feedTask = Task.detached(priority: .userInitiated) {
            for await buffer in stream { sink.feed(buffer) }
        }
    }

    // MARK: Dictation

    private func startDictation() {
        guard startTask == nil else { return }
        noticeTask?.cancel()
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
                try startCapture(into: sink)
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
                showNotice(.error(error.localizedDescription))
            }
        }
    }

    /// Stop listening, finalize, paste.
    private func finishDictation() {
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
                // Trailing space: the next dictation must not stick to this one.
                // Not after a break: the next dictation starts on the new line.
                await TextInserter.insert(text.hasSuffix("\n") ? text : text + " ")
            }
            Task { await engine.prewarm() }
        }
    }

    // MARK: Recording

    private func startRecording() {
        guard startTask == nil else { return }
        noticeTask?.cancel()
        state = .preparing
        indicator.show(.preparing(progress: nil))
        Log.app.info("Recording starting")

        startTask = Task { [self] in
            defer { startTask = nil }
            do {
                guard await Permissions.requestMicrophone() else { throw JisprError.microphoneDenied }
                try Task.checkCancellation()
                let writer = try RecordingWriter(url: Recordings.scratchURL(), format: audio.inputFormat)
                recording = writer
                try startCapture(into: writer)
                state = .recording
                indicator.model.elapsed = 0
                indicator.model.phase = .recording
                startClock()
                Log.app.info("Recording to \(writer.url.path, privacy: .public)")
            } catch is CancellationError {
                // Aborted before the file was made: nothing to clean up.
            } catch {
                Log.app.error("Recording failed to start: \(String(describing: error), privacy: .public)")
                audio.stop()
                recording?.discard()
                recording = nil
                state = .idle
                showNotice(.error(error.localizedDescription))
            }
        }
    }

    /// Stop recording and save the file as `~/Downloads/meeting_<seconds>_YYMMDD_HHMM.m4a`.
    private func finishRecording() {
        guard state == .recording, let writer = recording else { return }
        state = .finishing
        indicator.model.phase = .finishing
        stopClock()
        audio.stop()
        Log.app.info("Recording finishing")

        Task { [self] in
            await feedTask?.value
            feedTask = nil
            recording = nil
            do {
                let seconds = try writer.close()
                let url = Recordings.freeURL(
                    in: Recordings.downloads,
                    base: FileNaming.meetingName(at: Date()), ext: RecordingWriter.fileExtension
                )
                try FileManager.default.moveItem(at: writer.url, to: url)
                Log.app.info("Saved \(url.path, privacy: .public) (\(seconds, format: .fixed(precision: 1), privacy: .public) s)")
                state = .idle
                showNotice(.saved(url.lastPathComponent))
            } catch {
                Log.app.error("Saving the recording failed: \(String(describing: error), privacy: .public)")
                writer.discard()
                state = .idle
                showNotice(.error("Could not save the recording"))
            }
        }
    }

    private func startClock() {
        let started = Date()
        clockTask = Task { [self] in
            while !Task.isCancelled {
                indicator.model.elapsed = Date().timeIntervalSince(started)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    // MARK: Abort and notices

    /// Stop and throw the audio away. Nothing is pasted or saved.
    private func abort() {
        Log.app.info("Aborted")
        let wasStarting = startTask != nil
        let wasRecording = state == .recording
        startTask?.cancel()
        stopClock()
        audio.stop()
        feedTask?.cancel()
        feedTask = nil
        indicator.hide()
        state = .idle
        if let recording {
            recording.discard()
            self.recording = nil
        }
        if !wasStarting, !wasRecording {
            // Already listening: the start task is gone, so clean up the engine here.
            Task { [self] in
                await engine.cancel()
                await engine.prewarm()
            }
        }
    }

    /// Shows a short message in the pill, then hides it.
    private func showNotice(_ phase: IndicatorModel.Phase) {
        indicator.show(phase)
        noticeTask = Task { [self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, state == .idle else { return }
            indicator.hide()
        }
    }
}
