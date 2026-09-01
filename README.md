# Jispr

A tiny [Wispr Flow](https://wisprflow.ai)-style dictation app for macOS 26.
English only. Fully on-device, using Apple's `SpeechAnalyzer` / `SpeechTranscriber` (the same model as macOS dictation).
No accounts, no network, no settings.

## How it works

1. **Double-tap Right Option (⌥)** → Jispr starts listening. A small pill at the bottom of the screen shows *Listening* with a level meter.
2. Speak.
3. **Tap Right Option once** → Jispr stops and pastes the text where your cursor is.
4. **Escape** → abort. Nothing is pasted.

While Jispr is listening, Escape is swallowed so the front app never sees it.
The menu bar icon (a microphone) fills while a session is active. That is the whole UI.

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

- The app is **ad-hoc signed** by default. macOS ties the Accessibility grant to the binary, so after a rebuild the hotkey may stop working. Fix: remove Jispr from the Accessibility list and add it again. To avoid this, sign with a real certificate: `make bundle SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"`.
- Logs: `/usr/bin/log stream --level info --predicate 'subsystem == "io.github.b3nsten.jispr"'`
- Dev helper: `build/Jispr.app/Contents/MacOS/Jispr --transcribe some.aiff` prints the transcript of an audio file. Handy to test the speech pipeline without a microphone (`say -o test.aiff "hello"`).

## Layout

```
Sources/Jispr/
  JisprMain.swift          entry point (app or --transcribe)
  AppDelegate.swift        menu bar item, permission polling
  HotkeyMonitor.swift      CGEventTap: double-tap Right Option, Escape
  DictationController.swift  idle → preparing → listening → finishing
  Transcriber.swift        SpeechAnalyzer session, model download, prewarm
  AudioCapture.swift       AVAudioEngine mic tap + level meter
  BufferConverter.swift    resample mic audio to the model's format
  TextInserter.swift       pasteboard + synthetic ⌘V, restores old clipboard
  IndicatorPanel.swift / IndicatorView.swift   floating pill (non-activating panel)
Resources/Info.plist       LSUIElement, usage descriptions
Makefile                   build, bundle, sign, run, install
```
