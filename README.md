# Jispr

A tiny [Wispr Flow](https://wisprflow.ai)-style dictation app for macOS 26.
English only. Fully on-device. No accounts, no cloud, almost no settings.

## How it works

1. **Double-tap Right Option (⌥)** → Jispr starts listening. A small pill at the bottom of the screen shows *Listening* with a level meter.
2. Speak.
3. **Tap Right Option once** → Jispr stops and pastes the text where your cursor is, followed by one space, so the next dictation does not stick to it.
4. **Escape** → abort. Nothing is pasted.
5. **Triple-tap Right Option** → switch between dictating and recording to a file (see below). The pill shows the new mode.

While Jispr is listening, Escape is swallowed so the front app never sees it.
The menu bar icon (a microphone) fills while a session is active. That is almost the whole UI.

## Recording a meeting

Pick **Mode → Record to file** in the menu bar, or triple-tap Right Option. The same keys now record instead of dictate:

1. **Double-tap Right Option** → recording starts. The pill shows *Recording* with a level meter and a clock. The menu bar icon becomes a record dot.
2. **Tap Right Option once** → the recording is saved to `~/Downloads/meeting_<seconds>_YYMMDD_HHMM.m4a`, e.g. `meeting_1788442330_260902_1432.m4a`. The number is the exact save time in seconds since 1970 (for calculations); the rest is the local date and 24-hour time (for you). A name clash gets `-2`. AAC, small enough for hours.

   While you record, the audio goes to lossless 5-minute chunks in `~/Library/Application Support/Jispr/recordings/` (about 200 MB per hour, gone after the save), because an m4a is readable only once it is closed. On save, the chunks are decoded in order and encoded once into the AAC file. If Jispr crashes or the Mac loses power, at most 5 minutes are lost: at the next launch the chunks are joined and saved as `meeting_…-recovered.m4a` in Downloads, and Finder shows it. When the Mac sleeps or the microphone changes, the recording goes on afterwards, with a gap.
3. **Escape** → abort. The file is thrown away. After one minute of recording the pill asks first: click **Discard**, or **Keep** (Escape again keeps it too). The recording goes on while it asks.

**Transcribe Audio File…** in the menu picks any audio file (starts in Downloads), runs it through the selected engine and writes the text next to it as `.txt` (`meeting_1788442330_260902_1432.txt`). Finder shows the result. Keys are ignored while it runs. Long files take a moment: Parakeet needs roughly a minute per hour of audio on Apple silicon.

With Parakeet, files are transcribed by Parakeet v3, which detects the language on its own (German, English, 25 European languages in all; dictation stays on the English-only v2). The transcript is split by speaker, with the clock time of every turn:

```
Recorded 2026-09-02, 14:02–14:32

[14:02:05] Person 1: Good morning, everyone. Let us start with the budget for next quarter.

[14:02:41] Person 2: I disagree, the travel budget is already small.
```

The clock comes from the file name: the seconds give the exact save time, so the start is that minus the length of the audio. The local part of the name tells the time zone of the recording, so the times are shown as they were there, never UTC, even when you transcribe the file somewhere else. Older `meeting_YYMMDD_HHMM` names still work (the minute, plus the seconds from the file's "last changed" time). Other files get times counted from the start of the file, like `[0:41]`. Two limits: the clock assumes the audio ran without gaps, so a sleep or a microphone change in the middle shifts the times before the gap; and a recording across a summer-time switch is one hour off before the switch. Whoever speaks first is Person 1. Names are not known. With one speaker you get plain text. The speaker models ([`FluidInference/speaker-diarization-coreml`](https://huggingface.co/FluidInference/speaker-diarization-coreml), 21 MB, pyannote community-1 + WeSpeaker) are downloaded once on the first run. Limits: similar voices can be mixed up, and people talking over each other confuse it. Apple Speech gets the `Recorded` line but no speaker labels.

**Mode → Dictate (paste text)** or another triple tap switches back.

## Speech engines

Pick one in the menu bar under **Engine**. Default is Parakeet.

| Engine | What it is | Model |
|---|---|---|
| **Parakeet** (default) | NVIDIA Parakeet TDT 0.6B v2, English. Better with unusual words. Run on CoreML by [FluidAudio](https://github.com/FluidInference/FluidAudio). Audio files go through v3 instead: 25 European languages, detected automatically. | Downloaded once from Hugging Face ([`FluidInference/parakeet-tdt-0.6b-v2-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), and [`…-v3-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) on the first file) to `~/Library/Application Support/FluidAudio/Models/` (about 450 MB each). The pill shows the progress. |
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
  HotkeyMonitor.swift      CGEventTap: single, double and triple tap of Right Option, Escape
  DictationController.swift  idle → preparing → listening | recording → finishing; file transcription
  Recording.swift          Mode (dictate / record), Downloads naming
  RecordingWriter.swift    lossless chunk writer, one-pass AAC encode of the chunks, crash recovery
  FileTranscription.swift  feed a whole audio file into an engine (menu action and --transcribe)
  SpeechEngine.swift       engine protocol, engine choice (UserDefaults), text tidy
  ParakeetEngine.swift     Parakeet via FluidAudio, batch at the end: v2 for dictation, v3 + speaker labels for files
  AppleSpeechEngine.swift  SpeechAnalyzer session, streaming, model download
  AudioCapture.swift       AVAudioEngine mic tap + level meter, restart after sleep / device change
  BufferConverter.swift    resample mic audio to the model's format
  TextInserter.swift       pasteboard + synthetic ⌘V, restores old clipboard
  IndicatorPanel.swift / IndicatorView.swift   floating pill (non-activating panel)
Sources/JisprCore/
  TextCleanup.swift        transcript clean-up (pure, checked by make check)
  FileNaming.swift         meeting_<seconds>_YYMMDD_HHMM names and reading them back, -2/-3 suffixes (pure, checked)
  DateFormatters.swift     one fixed-format DateFormatter helper
  SpeakerAlignment.swift   words + "who spoke when" spans → timed Person 1 / Person 2 turns (pure, checked)
Resources/Info.plist       LSUIElement, usage descriptions
Makefile                   build, bundle, sign, run, install, cert
scripts/make-signing-cert.sh   one-time local signing certificate
```
