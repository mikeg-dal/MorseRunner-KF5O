# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS-native Qt 6 port of Alex Shovkoplyas (VE3NEA)'s Delphi/VCL **Morse Runner** CW contest simulator. The goal is **1:1 functional and visual parity** with the Windows original — DSP math, FSM transitions, scoring CRC32, message templates, and widget layout all trace back to the Pascal source. Deviations from the original are deliberate and documented (see `docs/parity-checklist.md`, `docs/mapping-pascal-to-cpp.md`).

Target: arm64, macOS 13+, Qt 6.10+, signed/notarized `.app` shipped as DMG. Bundle ID `com.garciamike1.morserunner`. **The CMake config hard-fails on non-Apple platforms** — cross-platform support is explicitly out of scope.

## Build / test / run

Configure presets live in `CMakePresets.json`; binary dirs are `build/<preset>/`.

```sh
# Configure + build (Ninja)
cmake --preset arm64-release
cmake --build --preset arm64-release --parallel

# Or use the wrapper: scripts/build.sh [--debug|--tsan|--asan]
# It auto-locates Qt via $QT_ROOT, falling back to `brew --prefix qt`.

# Run all tests (20 binaries: dsp, audio, simulation, scoring)
ctest --test-dir build/arm64-release --output-on-failure

# Run a single test binary directly
./build/arm64-release/tests/dsp/test_morse_keyer
./build/arm64-release/tests/dsp/test_morse_keyer --gtest_filter='MorseKeyerTest.Dot*'

# Launch the app
open build/arm64-release/MorseRunner.app
```

Sanitizer presets: `arm64-debug-tsan`, `arm64-debug-asan`. The threading model has been validated TSan-clean — keep it that way.

`CMAKE_EXPORT_COMPILE_COMMANDS=ON` is set in every preset for clangd / clang-tidy.

## Signing & shipping (only when releasing)

Two scripts; both are idempotent.

```sh
export QT_ROOT=/path/to/Qt/6.10.1/macos
export MR_SIGN_IDENTITY="Developer ID Application: <Name> (TEAMID)"
export MR_NOTARY_PROFILE=morserunner       # registered via `xcrun notarytool store-credentials`

./scripts/sign_and_notarize.sh   # deep-signs PlugIns + Frameworks, notarytool wait, staple
./scripts/make_dmg.sh            # UDRW → AppleScript window layout → UDZO → sign + staple
```

**Critical:** `sign_and_notarize.sh` re-signs every `Contents/PlugIns/**/*.dylib`. Qt ships its plugins signed under team `A5GTH44LYL`; our entitlements enforce library validation, so without the re-sign the app aborts at launch in `QGuiApplicationPrivate::createPlatformIntegration()`. Do not skip the deep-sign step or "simplify" it.

## Architecture (the parts that span files)

### Module layout (static libs under `src/`, linked into the bundle)

```
mr_app        AppController, main.cpp wiring
mr_ui         MainWindow, panels, custom-painted widgets, dialogs
mr_audio      AudioEngine (QAudioSink), SimulationWorker, SPSC rings
mr_simulation Contest, Station / MyStation / DxStation / DxOperator FSM, CallsignDb
mr_scoring    QsoLog, ExtractPrefix, ScoreWpx/Hst, CRC32
mr_dsp        MorseKeyer, MovingAverage, Modulator, AGC, QSB, …
mr_persistence Settings (QSettings plist) + INI key migration
mr_core       Constants, Theme, Random, Logging, WavWriter
mr_util       PlatformPaths, UrlOpener
```

Each subdir has its own `CMakeLists.txt` declaring a `mr_*` static lib. Tests under `tests/<area>/` link the corresponding `mr_*` and use GoogleTest (fetched via FetchContent, v1.15.2). No Qt-Test usage — gtest's float assertions are what the DSP determinism tests need.

### Threading (5 threads, all named for Instruments)

| Thread | Priority | Owns |
|---|---|---|
| `mr-main` | Default | Qt event loop, widgets, settings |
| `mr-sim` | High | `Contest::renderNextBlock()`, fills audio ring |
| `mr-audio` | TimeCritical | `QAudioSink`; pulls from ring, never blocks |
| `mr-wav` | Low | optional WAV recording (file I/O) |
| `mr-dbload` | Normal (one-shot) | Master.dta parse on startup |

Hand-offs — **do not introduce locks on the audio hot path**:

- **Sim → Audio**: `SpscRingBuffer<AudioFrame, 8>`. Audio thread writes silence + `underrunCount++` if empty; sim thread waits on `std::condition_variable` when full.
- **Sim → WAV**: `SpscRingBuffer<WavFrame, 64>`, drop-oldest on full.
- **Sim → GUI**: `GuiUpdateQueue` (latest-wins scalars + bounded 256-row log FIFO), drained by 30 Hz `QTimer` on GUI thread.
- **GUI → Sim (settings)**: `std::atomic<std::shared_ptr<const SettingsSnapshot>>`, read once per block at top of `renderNextBlock`. RCU-style.
- **GUI → Sim (commands)**: `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.

The original Delphi code bounces every audio buffer back to the GUI thread via `Synchronize` — that's exactly what this port eliminates. Do not reintroduce GUI-thread DSP work.

### Audio invariants (must match Pascal byte-for-byte)

- Sample rate **11025 Hz**, block size **512 samples**.
- Blackman-Harris keying envelopes, multi-pass moving-average LPF, identical modulator + AGC + QSB.
- Master.dta is the Pascal binary format (32 668 calls); parser lives in `src/simulation/CallsignDb.cpp`. The file is bundled into `Contents/Resources/data/`.

When tweaking DSP, the golden-WAV tests under `tests/dsp/` and `tests/golden/` are the contract. Don't change a filter coefficient and only fix unit tests — verify the golden output too.

### FSM & scoring contracts

- `DxOperator` state machine: `NeedPrevEnd → NeedQso → NeedNr → NeedCall/NeedCallNr → NeedEnd → Done/Failed`. `IsMyCall` uses Levenshtein with `?` wildcards.
- 22 message templates total, NR cut-numbers, LID error injection.
- Contest modes: Pile-Up, Single Calls, WPX Competition, HST Competition.
- WPX scoring: `Pts × Mul` with full `ExtractPrefix` portable-suffix handling. HST: sum of `CallToScore` Morse-element units.
- Score-submission CRC32 uses seed **`0xC90C2086`** and must match Pascal `PopupScoreWpx` byte-for-byte.

### Persistence

`QSettings` plist at `~/Library/Preferences/com.garciamike1.morserunner.plist`. All Pascal `Ini.pas` keys are preserved (migration in `mr_persistence`). User data (recordings, score history `.lst`, HiScore) lives under `~/Library/Application Support/MorseRunner/Morse Runner/`.

## Source-of-truth docs

- `docs/architecture.md` — layered diagram, thread/hand-off matrix.
- `docs/mapping-pascal-to-cpp.md` — Pascal unit → C++ module mapping.
- `docs/parity-checklist.md` — every widget/control vs the original `.dfm`, with status legend.
- `docs/constants-citations.md` — every numeric constant cited back to its Pascal source line.
- `docs/build-and-ship.md` — full signing/notarization/DMG workflow.

When changing parity-relevant behavior, update the relevant checklist entry in the same change.

## Code conventions

- C++20, `CMAKE_CXX_EXTENSIONS OFF`. Warnings via `cmake/CompileWarnings.cmake` (applied per target with `morserunner_apply_warnings`).
- `.clang-format` and `.clang-tidy` at the repo root. clang-tidy header filter is `src/.*\.(h|hpp)$` — tests and third-party are excluded by design.
- Tidy enables the broad `*` families but disables `cppcoreguidelines-avoid-magic-numbers` / `readability-magic-numbers` (DSP constants are everywhere) and `modernize-use-trailing-return-type`.
- Every source file carries the dual-copyright MPL-2.0 header (Shovkoplyas 2004-2006 / Garcia 2026). New files should too.
