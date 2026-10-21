# Porting Morse Runner to Swift

This package is the shipped macOS app's engine and app logic. It is a
native Swift port of the C++ engine under `../src/`.
That engine is itself a line-by-line port of VE3NEA's Delphi Morse Runner
v1.68 and is the **specification** for this one: the Swift code must
behave identically, sample for sample.

## How "identical" is checked

`../tools/golden/` holds small C++ programs (one per module) that drive the
C++ engine with fixed seeds and inputs and write reference data into
`Sources/MRTestSupport/Fixtures/<module>/`. Swift tests load that data with
`MRTestSupport.Fixtures` and require the Swift port to reproduce it.

```sh
../tools/golden/regenerate.sh dsp        # rebuild + rerun golden_dsp only
../tools/golden/regenerate.sh            # all modules
swift test                               # from Swift/
swift test --filter MRDSPTests
```

Compare with `==` (exact). A tolerance needs a written reason in the test;
"it was off by 1 ulp" is a porting bug to find, not a reason.

## Rules for bit-exact float code

1. **Same types.** Where the C++ uses `float`, use `Float`; `double` →
   `Double`. Convert at exactly the points the C++ converts
   (`static_cast<float>(x)` → `Float(x)`).
2. **Same expression order.** Keep the C++ operand order and grouping:
   `a * b * c` is `(a * b) * c`. Never simplify algebraically or hoist a
   product the C++ recomputes.
3. **No FMA.** Swift does not fuse `a * b + c`; the reference is built with
   `-ffp-contract=off` to match. Do not call `fma`/`addingProduct`.
4. **sin + cos of the same angle → `MRCore.sinCos(x)`.** Clang merges a
   `std::sin(x)`/`std::cos(x)` pair into one `__sincos_stret` call whose
   results can differ from separate calls. Use `sinCos` exactly where the
   C++ computes both for the same argument, and plain `sin`/`cos`
   everywhere else.
5. **Math functions.** `log`, `exp`, `pow`, `sin`, `cos` on `Float`
   arguments call the same libm `logf`/`expf`/... as the C++. Use
   `.squareRoot()` for `std::sqrt` (IEEE-exact either way).
6. **Rounding.** `mr::core::delphiRound(x)` → `delphiRound(x)` (round half
   to even). `static_cast<int>(x)` truncates toward zero → `Int(x)`.
   `std::floor`/`std::ceil` → `.rounded(.down)`/`.rounded(.up)`.
7. **Integers.** C++ `int` is 32-bit; Swift `Int` is 64-bit. Only matters
   if the C++ relies on overflow (it shouldn't); note it if it does.

## Rules for random numbers

`MRCore.Random` reproduces the C++ `mr::core::Random` exactly (MT19937 and
every helper). Consume draws **in the same order** as the C++: same call
sites, same loop structure, same short-circuiting (`a && rng.x()` must not
draw when `a` is false). Clang evaluates function arguments and binary
operands left to right, as Swift does.

## Layout and ownership

| Target | Ports | C++ source |
|---|---|---|
| MRCore | constants, Delphi rounding, Random, sinCos, WavWriter | `src/core` |
| MRDSP | Blackman-Harris, MorseTable, MorseKeyer, MovingAverage, PingPongFilter, QuickAverage, Qsb, Modulator, Agc, ComplexBuf | `src/dsp` |
| MRScoring | CallToScore, ExtractPrefix, Crc32, QsoLog | `src/scoring` |
| MRSimulation | Engine, Messages, NumberFormat, IsMyCall, Station, DxOperator, DxStation, MyStation, QrmStation, QrnStation, StationCollection, CallsignDb/Source, Contest | `src/simulation` |
| MRAudio | SPSC ring, AVAudioEngine output, simulation thread | `src/audio` |
| MRPersistence | settings (UserDefaults) | `src/persistence` |

- Do not edit `Package.swift`, any `CMakeLists.txt`, or another module's
  directory. Module `X`'s reference dump is `../tools/golden/golden_X.cpp`
  only.
- Every file starts with the dual-copyright MPL-2.0 header (copy it from
  any existing `.swift` file).
- Keep the C++ comments that cite Pascal behaviour; they are the paper
  trail for parity.
- Swift 6 language mode. Engine types are single-threaded classes owned by
  the simulation thread; don't add locks or actors inside the engine.
- Tests use Swift Testing (`import Testing`).

## Context

- The original Pascal source (for questions the C++ doesn't answer) is a
  clone of https://github.com/VE3NEA/MorseRunner.
- `../docs/` documents the C++ port; `../CLAUDE.md` describes the threading
  model that MRAudio must keep (no locks or allocation on the audio thread).

## Working in parallel

Use your own build directories so concurrent builds don't block each
other:

```sh
swift build --scratch-path .build-<module>
swift test  --scratch-path .build-<module> --filter MR<Module>Tests
GOLDEN_BUILD_DIR=../build/golden-<module> ../tools/golden/regenerate.sh <module>
```

## MRSimulation public API (fixed — the app is written against it)

```swift
public enum RunMode: Int { case stop = 0, pileUp, single, wpx, hst }

public enum Message: Int {   // raw values = C++ mr::sim::Message
    case none = 0, cq, nr, tu, myCall, hisCall, b4, qm, nilMsg, garbage,
         rNr, rNr2, deMyCall1, deMyCall2, deMyCallNr1, deMyCallNr2, nrQm,
         longCq, myCallNr2, qrl, qrl2, qsy, agn
}

public struct ContestSettings {   // same fields and defaults as C++
    public var myCallsign = "VE3NEA", wpm = 30, pitchHz = 600, rxBandwidthHz = 500,
               ritHz = 0, qsk = true, qrn = true, qrm = true, qsb = true,
               flutter = true, lids = true, activity = 3, durationMinutes = 30
    public var selfMonGain01: Float = 0.75
    public var callsFromKeyer = false
    public var mode: RunMode = .pileUp
}

public final class Contest {
    public init(calls: CallsignSource, bufferSize: Int, random: Random)
    public var settings: ContestSettings { get }
    public func setSettings(_ s: ContestSettings)
    public func setRunMode(_ m: RunMode)
    public var runMode: RunMode { get }
    public func playerSendMessage(_ m: Message, callField: String = "")
    public func playerEditedCall(_ callField: String) -> Bool
    public func qsoLogged(_ call: String)
    public struct AbortInfo { public let hadHisCall: Bool; public let hadNr: Bool }
    public func playerAbortSend() -> AbortInfo
    public func requestStop()
    public func renderNextBlock(into out: UnsafeMutableBufferPointer<Float>) -> Int
    public var currentBlockIndex: Int { get }
    public var bufferSize: Int { get }
    public var playerSending: Bool { get }
    public var stations: StationCollection { get }
    public var player: MyStation { get }
    @discardableResult public func enableAudioRecording(path: String) -> Bool ; public func disableAudioRecording()
    public struct CompletedQso { public let call: String; public let rst: Int; public let nr: Int; public let minute: Float }
    public var onEndOfSession: ((RunMode, _ stoppedByUser: Bool) -> Void)?
    public var onQsoCompleted: ((CompletedQso) -> Void)?
    public var onPlayerPieceFinished: (() -> Void)?
}

public final class CallsignDb: CallsignSource { public init(); public func load(from url: URL) -> Bool; public var count: Int { get } }
```
