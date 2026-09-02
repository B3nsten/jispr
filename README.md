# Jispr

A tiny [Wispr Flow](https://wisprflow.ai)-style dictation app for macOS 26.
English only. Fully on-device. No accounts, no cloud, almost no settings.

## How it works

1. **Double-tap Right Option (⌥)** → Jispr starts listening. A small pill at the bottom of the screen shows *Listening* with a level meter.
2. Speak.
3. **Tap Right Option once** → Jispr stops and pastes the text where your cursor is, followed by one space, so the next dictation does not stick to it.
4. **Escape** → abort. Nothing is pasted.

While Jispr is listening, Escape is swallowed so the front app never sees it.
The menu bar icon (a microphone) fills while a session is active. That is almost the whole UI.

## Recording a meeting

Pick **Mode → Record to file** in the menu bar. The same keys now record instead of dictate:

1. **Double-tap Right Option** → recording starts. The pill shows *Recording* with a level meter and a clock. The menu bar icon becomes a record dot.
2. **Tap Right Option once** → the recording is saved to `~/Downloads/meeting_YYMMDD_HHMM.m4a` (date and 24-hour time of the save, e.g. `meeting_260902_1432.m4a`; a second one in the same minute becomes `meeting_260902_1432-2.m4a`). AAC, small enough for hours.
3. **Escape** → abort. The file is thrown away.

**Transcribe Audio File…** in the menu picks any audio file (starts in Downloads), runs it through the selected engine and writes the text next to it as `.txt` (`meeting_260902_1432.txt`). Finder shows the result. Keys are ignored while it runs. Long files take a moment: Parakeet needs roughly a minute per hour of audio on Apple silicon.

With Parakeet the transcript is split by speaker:

```
Person 1: Good morning, everyone. Let us start with the budget for next quarter.

Person 2: I disagree, the travel budget is already small.
```

Whoever speaks first is Person 1. Names are not known. With one speaker you get plain text. The speaker models ([`FluidInference/speaker-diarization-coreml`](https://huggingface.co/FluidInference/speaker-diarization-coreml), 21 MB, pyannote community-1 + WeSpeaker) are downloaded once on the first run. Limits: similar voices can be mixed up, and people talking over each other confuse it. Apple Speech has no speaker labels.

**Mode → Dictate (paste text)** switches back.

## Speech engines

Pick one in the menu bar under **Engine**. Default is Parakeet.

| Engine | What it is | Model |
|---|---|---|
| **Parakeet** (default) | NVIDIA Parakeet TDT 0.6B v2, English. Better with unusual words. Run on CoreML by [FluidAudio](https://github.com/FluidInference/FluidAudio). | Downloaded once from Hugging Face ([`FluidInference/parakeet-tdt-0.6b-v2-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)) to `~/Library/Application Support/FluidAudio/Models/` (about 450 MB). The pill shows the progress. |
| **Apple Speech** | Apple's `SpeechAnalyzer` built into macOS 26. | System model, shared with macOS dictation. |

Parakeet transcribes the whole recording when you stop, so long dictations take a moment longer to paste. Apple Speech streams while you talk.

## Text clean-up

Every transcript goes through a small, deterministic clean-up before it is pasted (`Sources/JisprCore/TextCleanup.swift`, checked by `make check`):

- capital letter at the start and after `. ! ?`
- "i" becomes "I" (also "i'm", "i'll", ...)
- no space before punctuation, one space after `, ; : ! ?`
- a final period when the text ends in a letter or digit
- Voice commands: say **"new paragraph"** (empty line) or **"new line"** (single break) after a short pause. The pause shows up as punctuation, and that is what makes it a command. Inside a running sentence ("I started a new paragraph in the essay") the words stay words. If you said the command without a pause, it stays as text. Nothing is lost.
- Parakeet only: shouted words such as `JISPR` become names (`Jispr`). Known acronyms (NASA, HTML, ...) and words of three letters or fewer (AI, USB) stay. Add your own with:

```sh
defaults write io.github.b3nsten.jispr keepCaps -array WWDC FOOBAR
```

## Requirements

- macOS 26 (Tahoe) on Apple silicon
- Xcode Command Line Tools with Swift 6.2 (`xcode-select --install`)

## Build and run

```sh
make run          # builds build/Jispr.app and opens it
make install      # copies it to /Applications
```

## Permissions (first run)

| Permission | Why | Where |
|---|---|---|
| Accessibility | global hotkey + pasting into the front app | System Settings → Privacy & Security → Accessibility → add **Jispr** |
| Microphone | hearing you | macOS asks on your first dictation |

If the English speech model is not on your Mac yet, Jispr downloads it on first use and shows the progress in the pill.

## Notes

- **Signing.** macOS ties the Accessibility grant to the app signature. Run `make cert` once: it creates a self-signed certificate *Jispr Local Signing* in your login keychain (macOS asks for your password). The Makefile picks it up automatically, so the grant survives rebuilds. Without it the app is ad-hoc signed, and you must remove and re-add Jispr in Accessibility after every rebuild. You can also pass your own: `make bundle SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"`.
- Logs: `/usr/bin/log stream --level info --predicate 'subsystem == "io.github.b3nsten.jispr"'`
- Dev helper: `build/Jispr.app/Contents/MacOS/Jispr --transcribe some.aiff [parakeet|apple]` prints the transcript of an audio file. Handy to test the speech pipeline without a microphone (`say -o test.aiff "hello"`).

## Layout

```
Sources/Jispr/
  JisprMain.swift          entry point (app or --transcribe)
  AppDelegate.swift        menu bar item, permission polling
  HotkeyMonitor.swift      CGEventTap: double-tap Right Option, Escape
  DictationController.swift  idle → preparing → listening | recording → finishing; file transcription
  Recording.swift          Mode (dictate / record), AAC file writer, Downloads naming
  FileTranscription.swift  feed a whole audio file into an engine (menu action and --transcribe)
  SpeechEngine.swift       engine protocol, engine choice (UserDefaults), text tidy
  ParakeetEngine.swift     Parakeet v2 via FluidAudio, batch at the end; speaker labels for files
  AppleSpeechEngine.swift  SpeechAnalyzer session, streaming, model download
  AudioCapture.swift       AVAudioEngine mic tap + level meter
  BufferConverter.swift    resample mic audio to the model's format
  TextInserter.swift       pasteboard + synthetic ⌘V, restores old clipboard
  IndicatorPanel.swift / IndicatorView.swift   floating pill (non-activating panel)
Sources/JisprCore/
  TextCleanup.swift        transcript clean-up (pure, checked by make check)
  FileNaming.swift         meeting_YYMMDD_HHMM names, -2/-3 suffixes (pure, checked)
  SpeakerAlignment.swift   words + "who spoke when" spans → Person 1 / Person 2 turns (pure, checked)
Resources/Info.plist       LSUIElement, usage descriptions
Makefile                   build, bundle, sign, run, install, cert
scripts/make-signing-cert.sh   one-time local signing certificate
```
