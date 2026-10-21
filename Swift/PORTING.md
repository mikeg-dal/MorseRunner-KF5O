# Engine rules (bit-exact parity)

This package is the macOS app's engine and app logic. The engine was
ported line by line from an earlier C++ port of VE3NEA's Delphi Morse
Runner 1.68, and must keep behaving identically to it, sample for sample.

That C++/Qt port is no longer in the tree. It is preserved at the git tag
**`cpp-qt-reference`**. Comments such as "Port of src/dsp/Agc.cpp" or "C++
src/simulation/Contest" refer to files at that tag.

## How "identical" is checked

`Sources/MRTestSupport/Fixtures/<module>/` holds reference data that the
C++ engine wrote with fixed seeds and inputs: random sequences, keyer
envelopes, filter and AGC outputs, scoring tables, edge cases, and six
whole-contest traces. The Swift tests load it with `MRTestSupport.Fixtures`
and require the Swift engine to reproduce it with `==`.

```sh
swift test                               # from Swift/
swift test --filter MRDSPTests
```

A tolerance needs a written reason in the test; "it was off by 1 ulp" is a
bug to find, not a reason.

The fixtures are frozen. If a deliberate behaviour change alters the
engine's output:

1. Confirm the new behaviour against the Pascal source
   (https://github.com/VE3NEA/MorseRunner).
2. Either regenerate the data from the C++ port with the same change
   (`git worktree add ../mr-cpp cpp-qt-reference`, edit, then
   `tools/golden/regenerate.sh` there; needs CMake and Qt 6), or update
   the affected fixture from the Swift engine and explain why in the
   commit.
3. Record the change in `../docs/parity-checklist.md`.

## Rules for bit-exact float code

1. **Same types.** Keep `Float` where the engine uses `Float` and `Double`
   where it uses `Double`; convert at exactly the existing points.
2. **Same expression order.** `a * b * c` is `(a * b) * c`. Never simplify
   algebraically or hoist a product that is recomputed.
3. **No FMA.** Swift does not fuse `a * b + c` (the reference was built
   with `-ffp-contract=off`). Do not call `fma`/`addingProduct`.
4. **sin + cos of the same angle → `MRCore.sinCos(x)`** at the sites that
   already use it (clang merged those pairs into `__sincos_stret` in the
   reference). Plain `sin`/`cos` everywhere else.
5. **Math functions.** `log`, `exp`, `pow`, `sin`, `cos` on `Float` call
   the same libm `logf`/`expf`/… the reference used. `.squareRoot()` is
   IEEE-exact.
6. **Rounding.** Pascal `Round` → `delphiRound(x)` (half to even).
   Truncation → `Int(x)`. `floor`/`ceil` → `.rounded(.down)`/`.rounded(.up)`.
7. **Integers.** The reference used 32-bit `int`; Swift `Int` is 64-bit.
   Only matters where code relies on overflow; note it if it does.

## Rules for random numbers

`MRCore.Random` reproduces MT19937 and every helper of the reference.
Never change the order or number of draws: same call sites, same loop
structure, same short-circuiting (`a && rng.x()` must not draw when `a` is
false). Swift evaluates arguments and operands left to right.

## Layout

| Target | Contents |
|---|---|
| MRCore | constants, Delphi rounding, Random, sinCos, byte strings, WavWriter |
| MRDSP | Blackman-Harris, MorseTable, MorseKeyer, MovingAverage, PingPongFilter, QuickAverage, Qsb, Modulator, Agc, ComplexBuf |
| MRScoring | CallToScore, ExtractPrefix, Crc32, QsoLog |
| MRSimulation | Engine, Messages, NumberFormat, IsMyCall, Station, DxOperator, DxStation, MyStation, QrmStation, QrnStation, StationCollection, CallsignDb/Source, Contest |
| MRAudio | SPSC block ring, AVAudioEngine output, simulation thread |
| MRPersistence | settings (UserDefaults, Ini.pas keys) |
| MRAppCore | UI-independent app logic (keys, Enter Sends Message, Run rules, captions, end of contest, score files) |
| MRTestSupport | fixture loader and the frozen reference data |

- Every file starts with the dual-copyright MPL-2.0 header (copy it from
  any existing `.swift` file).
- Keep comments that cite Pascal behaviour; they are the paper trail for
  parity.
- Engine types are single-threaded classes owned by the simulation
  thread; don't add locks or actors inside the engine. No locks or
  allocation on the audio render thread.
- Tests use Swift Testing (`import Testing`).

## MRSimulation public API (the app is written against it)

```swift
public enum RunMode: Int { case stop = 0, pileUp, single, wpx, hst }

public enum Message: Int {
    case none = 0, cq, nr, tu, myCall, hisCall, b4, qm, nilMsg, garbage,
         rNr, rNr2, deMyCall1, deMyCall2, deMyCallNr1, deMyCallNr2, nrQm,
         longCq, myCallNr2, qrl, qrl2, qsy, agn
}

public struct ContestSettings {
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
