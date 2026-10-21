# Morse Runner for macOS

A native macOS port of [Morse Runner](https://www.dxatlas.com/MorseRunner/),
the CW contest simulator by Alex Shovkoplyas, VE3NEA (2004–2006), written in
Swift and AppKit.

The goal is **1:1 parity with Morse Runner 1.68 for Windows**: the same
audio, the same simulated stations, the same scoring and the same form
layout. Every deliberate difference is listed in
[`docs/parity-checklist.md`](docs/parity-checklist.md).

- **Download:** signed and notarized builds are on the
  [Releases](https://github.com/mikeg-dal/MorseRunner-KF5O/releases) page.
- **Requires:** macOS 15 or later. Universal app (Apple Silicon and Intel).
- **License:** Mozilla Public License 2.0, as the original. See `LICENSE`.

## How it is built

| Part | What it is |
|---|---|
| `Swift/` | **The app.** A Swift package (engine + app logic) and an AppKit app generated with xcodegen. |
| `src/`, `tests/`, `CMakeLists.txt` | The earlier C++/Qt 6 port. It is kept as the **reference implementation**: the Swift engine is tested sample for sample against it. |
| `tools/golden/` | Small C++ programs that run the reference engine with fixed seeds and write the data the Swift tests compare against. |
| `resources/` | `Master.dta` (the original 32,668-call database), icon, entitlements, Readme. |
| `docs/` | Parity checklist, architecture, build and release notes, Pascal cross-references. |

The Swift package is split into modules that mirror the original Pascal
units:

```
Swift/
├── Package.swift
├── project.yml              xcodegen spec for the app + app-hosted tests
├── App/Sources/             AppKit: window, menus, custom-drawn widgets
├── App/Tests/               app-hosted tests (Swift Testing)
├── Sources/
│   ├── MRCore/              constants, Delphi rounding, MT19937 random, WAV writer
│   ├── MRDSP/               keyer, filters, modulator, AGC, QSB
│   ├── MRScoring/           QSO log, WPX prefixes, HST points, score CRC
│   ├── MRSimulation/        contest, stations, DX operator state machine, Master.dta
│   ├── MRAudio/             AVAudioEngine output, lock-free ring, simulation thread
│   ├── MRPersistence/       settings (UserDefaults, same keys as Ini.pas)
│   ├── MRAppCore/           UI-independent app logic: keys, Enter-sends-message,
│   │                        Run rules, captions, end-of-contest scoring, score files
│   └── MRTestSupport/       reference data from tools/golden
└── Tests/                   one test target per module
```

## Build and test

Needs Xcode 26 (Swift 6.2) and `xcodegen` (`brew install xcodegen`).

```sh
cd Swift

# Engine and app-logic tests
swift test

# Generate the Xcode project, build and run the app
xcodegen generate
xcodebuild -project MorseRunner.xcodeproj -scheme MorseRunner -derivedDataPath .build-app build
open .build-app/Build/Products/Debug/MorseRunner.app

# All tests, including the app-hosted ones
xcodebuild -project MorseRunner.xcodeproj -scheme MorseRunner -derivedDataPath .build-app test
```

The reference data in `Swift/Sources/MRTestSupport/Fixtures` is generated
from the C++ engine; regenerating it needs CMake and Qt 6 (see
[`docs/build-and-ship.md`](docs/build-and-ship.md)).

## Release

```sh
export MR_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
export MR_TEAM_ID=<TEAMID>
export MR_NOTARY_PROFILE=<notarytool keychain profile>
scripts/release_swift.sh
```

This builds a universal Release app, signs it with the hardened runtime,
notarizes and staples it, and writes `dist/MorseRunner-<version>-macOS.zip`.
Publish the zip as a GitHub Release asset; it is not committed.

## Threading

The original runs its audio rendering on the GUI thread (`Synchronize`).
This port keeps the GUI thread free of DSP:

| Thread | Does |
|---|---|
| main | AppKit, input, settings; sends commands to the simulation |
| `mr-sim` | `Contest.renderNextBlock()`, fills the audio ring |
| Core Audio render thread | copies finished blocks out of the ring; no locks or allocation |

Commands go GUI → simulation through a queue drained by the `mr-sim`
thread; events come back to the main thread. Details in
[`docs/architecture.md`](docs/architecture.md).

## Parity

Matches the original in:

- **Audio:** 11025 Hz, 512-sample blocks, Blackman-Harris keying, the same
  filters, modulator, AGC and QSB, and the Pascal `Round` (half to even).
- **Stations:** the DX operator state machine, `IsMyCall` with `?`
  wildcards, all message templates, cut numbers, LID errors, QRM and QRN.
- **Modes:** Pile-Up, Single Calls, WPX Competition, HST Competition.
- **Scoring:** WPX points × prefixes, HST Morse-unit points, the
  CRC-stamped score line of `PopupScoreWpx`.
- **Operating:** Enter Sends Message, F1–F8, Space, Esc, `.`/`+`/`[`/`,`
  TU and log, F11 / Alt-W / Ctrl-W wipe, Up/Down RIT, PgUp/PgDn speed.
- **Settings:** the same keys and defaults as `Ini.pas`.

Deliberate differences:

- Cut numbers typed into RST and Nr. are converted as you type
  (T/O → 0, N → 9).
- The RIT marker can be dragged, as well as clicked.
- Standard macOS menus (Edit, Window, Hide), and Command works where the
  original uses Ctrl.
- A "Ported to macOS" credit on the start screen.

## Files

- Settings: `~/Library/Preferences/com.garciamike1.MorseRunner.plist`
- Score history, HST results and recordings:
  `~/Library/Application Support/MorseRunner/`

## Acknowledgments

- **Alex Shovkoplyas, VE3NEA**: the original Morse Runner (Delphi,
  2004–2006). The DSP, the station behaviour and the layout of this port
  trace back to his code.
- **Mike Garcia, KF5O**: macOS port (2026).

Released under the Mozilla Public License 2.0. See `LICENSE`.
