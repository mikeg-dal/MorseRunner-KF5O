# Morse Runner — macOS-native Qt 6 port

A native macOS app for Apple Silicon that reproduces the beloved Windows
amateur-radio CW contest simulator [Morse Runner](http://www.dxatlas.com/MorseRunner/)
by Alex Shovkoplyas, VE3NEA (2004–2006).

**1:1 functional and visual parity** with the Windows original, but fully
native: signed/notarized `.app` bundle, hardened runtime, distributable
via DMG with drag-to-Applications layout.

- **License**: Mozilla Public License 2.0 (preserved from the original)
- **Architecture**: arm64 (Apple Silicon)
- **Minimum macOS**: 13.0 (Ventura)
- **Bundle ID**: `com.garciamike1.morserunner`
- **Build**: CMake 3.28+ · Qt 6.10+ · Xcode command-line tools

## What's in here

A complete signed, notarized, distributable build is sitting in
`build/arm64-release/MorseRunner-1.68.dmg` (~41 MB).

```
.
├── CMakeLists.txt           top-level build
├── CMakePresets.json        arm64-debug | arm64-release | arm64-debug-tsan
├── cmake/                   sign / notarize / bundle helpers
├── resources/
│   ├── data/Master.dta      32 668-call database (bundled into .app/Contents/Resources/data)
│   ├── icons/MorseRunner.icns
│   ├── Info.plist.in
│   └── MorseRunner.entitlements   hardened runtime, no sandbox
├── scripts/
│   ├── build.sh
│   ├── sign_and_notarize.sh   deep-signs PlugIns + Frameworks, notarytool wait
│   └── make_dmg.sh            UDRW → AppleScript window layout → UDZO + sign + staple
├── src/
│   ├── app/         AppController, main.cpp
│   ├── audio/       AudioEngine (QAudioSink), SimulationWorker, SPSC ring
│   ├── core/        Constants.h, Theme, Logging, Random, WavWriter
│   ├── dsp/         MorseKeyer, MovingAverage, Modulator, AGC, QSB, …
│   ├── persistence/ Settings (QSettings → ~/Library/Preferences plist)
│   ├── scoring/     CallToScore, ExtractPrefix, CRC32
│   ├── simulation/  Contest, Station / MyStation / DxStation / DxOperator FSM
│   │                CallsignDb (Pascal Master.dta parser)
│   └── ui/          MainWindow + panels + custom widgets + dialogs
└── tests/           20 GoogleTest binaries (dsp, simulation, scoring, audio)
```

## Quick start

```sh
# Configure (Ninja generator, arm64-release preset)
cmake --preset arm64-release

# Build the .app
cmake --build build/arm64-release

# Run tests (expects 20/20)
ctest --test-dir build/arm64-release --output-on-failure

# Launch
open build/arm64-release/MorseRunner.app
```

For a Debug build with ThreadSanitizer:

```sh
cmake --preset arm64-debug-tsan
cmake --build build/arm64-debug-tsan
ctest --test-dir build/arm64-debug-tsan
```

## Signing, notarizing, and shipping a DMG

One-time setup (already done on this machine):

1. Import your Developer ID Application certificate into the login keychain
   (double-click the `.p12` and supply its password).
2. Register a notarytool credential profile:
   ```sh
   xcrun notarytool store-credentials morserunner \
       --key /path/to/AuthKey_XXXXX.p8 \
       --key-id XXXXXXXXXX \
       --issuer <UUID-from-App-Store-Connect>
   ```

Then for each ship:

```sh
export QT_ROOT=/path/to/Qt/6.10.1/macos      # for macdeployqt
export MR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export MR_NOTARY_PROFILE=morserunner

cmake --build build/arm64-release
./scripts/sign_and_notarize.sh    # deep-sign PlugIns + Frameworks, notarize+staple
./scripts/make_dmg.sh             # UDRW staging, AppleScript window layout, UDZO, sign+notarize+staple
```

The DMG lands at `build/arm64-release/MorseRunner-1.68.dmg`. Opening it
shows the `.app` on the left and an `Applications` symlink on the right —
standard drag-to-install layout.

**Critical signing detail:** `sign_and_notarize.sh` deep-signs every
`Contents/PlugIns/**/*.dylib` first. The Qt Company ships its plugins
signed under team `A5GTH44LYL`; our entitlements enforce library
validation, so without our re-signing pass the app aborts at launch
with `QGuiApplicationPrivate::createPlatformIntegration() → fatal`.

## Threading

The original Delphi build ran `TContest.GetAudio` on the GUI thread via
`Synchronize`. This port uses five threads with lock-free SPSC hand-off:

| Thread | Priority | Responsibility |
|---|---|---|
| `mr-main` | Normal | GUI, widget paint, user input only |
| `mr-sim` | High | Runs `Contest::renderNextBlock()`, fills audio ring |
| `mr-audio` | TimeCritical | Owns `QAudioSink`; pulls from ring, never blocks |
| `mr-wav` | Low | Drains optional WAV recording (file I/O) |
| `mr-dbload` | Normal (one-shot) | Parses Master.dta on startup |

The sim thread paces itself off the 8-slot ring depth; UI updates flow
back via `QueuedConnection` signals. ThreadSanitizer-clean.

## Parity status (vs Windows original)

✅ **Full parity:**
- Audio DSP: identical 11025 Hz, 512-sample blocks, same Blackman-Harris keying envelopes, same multi-pass moving-average LPF, same modulator + AGC + QSB.
- FSM: `DxOperator` state machine (NeedPrevEnd → NeedQso → NeedNr → NeedCall/NeedCallNr → NeedEnd → Done/Failed), full `IsMyCall` Levenshtein with `?` wildcards.
- Messaging: all 22 message templates, NR cut-numbers, LID error injection.
- Contest modes: Pile-Up, Single Calls, WPX Competition, HST Competition.
- Master.dta: full 32 668-call DXCC database, Pascal-format binary parser.
- Scoring: WPX (Pts × Mul with full `ExtractPrefix` portable-suffix handling), HST (sum of `CallToScore` Morse-element units).
- Score string + CRC32: matches `PopupScoreWpx` byte-for-byte; seed `0xC90C2086`.
- Persistence: `QSettings` plist with all Pascal Ini.pas keys + score history `.lst` file.
- Keyboard: F1-F8 send, Space focus rotation, Esc abort, F11/Ctrl-W wipe, Up/Down RIT ±50 Hz, `.`/`+`/`[` TU+SaveQso.
- End-of-session: rich `ScoreDialog` for WPX-family, simple alert for HST.

✅ **macOS-native additions:**
- Drag-to-Applications DMG layout.
- Settings persisted to `~/Library/Preferences/com.garciamike1.morserunner.plist`.
- Audio recordings, score history, and HiScore in `~/Library/Application Support/MorseRunner/Morse Runner/`.
- Accessibility labels + descriptions on every interactive widget for VoiceOver.
- macOS dark-mode chrome (title bar, menu bar) via Qt 6 + QStyleHints; in-app widgets keep Pascal-faithful colors by design.

🛑 **Intentional deviations:**
- Custom-painted widgets (histogram, RIT slider) keep their Pascal colors in both light and dark mode — that's part of the simulator's visual identity.
- Score-board POST is "open URL in browser" rather than auto-submit (matches Pascal `OpenWebPage`).

## How to run a contest

1. **File → Audio Recording Enabled** (optional, if you want a WAV)
2. **Run** button (or Run menu → Pile-Up / Single Calls / WPX Competition / HST Competition)
3. As you hear DX stations call you, type their call in the **Call** field
4. **F5** sends your guess; if correct, DX replies asking for your number
5. **F2** sends your number
6. DX sends `R 5NN ###` (their number)
7. Type their number in **Nr**, then **`.` or `+` or `[`** sends TU and logs the QSO in one keystroke (or **F3** then **Enter**)
8. Score table updates live; histogram bar grows; clock ticks

When the duration timer runs out you get either:
- **WPX-family** (Pile-Up / Single Calls / WPX Competition): rich
  `ScoreDialog` with `YYYY-MM-DD <call> <pts> <mult> [<CRC32>]`
  submission string + Scoreboard button + green "Congratulations on a
  new record!" banner if you beat your stored HiScore.
- **HST Competition**: bare "Score: N" message box.

## Acknowledgments

- **Alex Shovkoplyas, VE3NEA** — original Delphi/VCL Morse Runner
  (2004–2006). The DSP math, FSM logic, and visual layout in this port
  trace directly back to his code.
- **Mike Garcia, KF5O** — macOS Qt 6 port (2026).

Released under the Mozilla Public License 2.0. See `LICENSE`.
