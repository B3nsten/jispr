# Jispr

A tiny [Wispr Flow](https://wisprflow.ai)-style dictation app for macOS 26.
English only. Fully on-device. No accounts, no cloud, almost no settings.

## How it works

1. **Double-tap Right Option (⌥)** → Jispr starts listening. A small pill at the bottom of the screen shows *Listening* with a level meter.
2. Speak.
3. **Tap Right Option once** → Jispr stops and pastes the text where your cursor is.
4. **Escape** → abort. Nothing is pasted.

While Jispr is listening, Escape is swallowed so the front app never sees it.
The menu bar icon (a microphone) fills while a session is active. That is the whole UI.

## Speech engines

Pick one in the menu bar under **Engine**. Default is Parakeet.

| Engine | What it is | Model |
|---|---|---|
| **Parakeet** (default) | NVIDIA Parakeet TDT 0.6B v2, English. Better with unusual words. Run on CoreML by [FluidAudio](https://github.com/FluidInference/FluidAudio). | Downloaded once from Hugging Face ([`FluidInference/parakeet-tdt-0.6b-v2-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)) to `~/Library/Application Support/FluidAudio/Models/` (about 450 MB). The pill shows the progress. |
| **Apple Speech** | Apple's `SpeechAnalyzer` built into macOS 26. | System model, shared with macOS dictation. |

Parakeet transcribes the whole recording when you stop, so long dictations take a moment longer to paste. Apple Speech streams while you talk.

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
  DictationController.swift  idle → preparing → listening → finishing
  SpeechEngine.swift       engine protocol, engine choice (UserDefaults), text tidy
  ParakeetEngine.swift     Parakeet v2 via FluidAudio, batch at the end
  AppleSpeechEngine.swift  SpeechAnalyzer session, streaming, model download
  AudioCapture.swift       AVAudioEngine mic tap + level meter
  BufferConverter.swift    resample mic audio to the model's format
  TextInserter.swift       pasteboard + synthetic ⌘V, restores old clipboard
  IndicatorPanel.swift / IndicatorView.swift   floating pill (non-activating panel)
Resources/Info.plist       LSUIElement, usage descriptions
Makefile                   build, bundle, sign, run, install, cert
scripts/make-signing-cert.sh   one-time local signing certificate
```
