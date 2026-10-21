// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Ports of the C++ unit tests in tests/dsp/*.cpp. These are behavioural
// sanity checks; the tolerances below are the ones the C++ tests use for
// physical properties (RMS, DC convergence, energy), not porting slack —
// exactness against the C++ is covered by DspFixtureTests.

import Foundation
import MRCore
@testable import MRDSP
import Testing

private let sr = AudioK.sampleRate

// MARK: - test_agc.cpp

@Suite struct AgcTests {
    private func makeAgc(enabled: Bool) -> Agc {
        let agc = Agc()
        agc.setMaxOut(20000)
        agc.setNoiseInDb(0)
        agc.setNoiseOutDb(60)  // gain ≈ 1000
        agc.setEnabled(enabled)
        return agc
    }

    @Test func bypassedAppliesDefaultGain() {
        let agc = makeAgc(enabled: false)
        var data = [Float](repeating: 1, count: 64)
        agc.process(&data)
        for s in data {
            #expect(abs(s - 1000) <= 1)
        }
    }

    @Test func bypassedClampsToMaxOut() {
        let agc = makeAgc(enabled: false)
        var data: [Float] = [50, -50, 100]
        agc.process(&data)
        #expect(data == [20000, -20000, 20000])
        #expect(agc.isOverload)
    }

    @Test func enabledStaysFiniteOnStep() {
        let agc = makeAgc(enabled: true)
        agc.setAttackSamples(155)
        agc.setHoldSamples(155)
        var data = [Float](repeating: 0, count: 2048)
        for i in 512..<data.count { data[i] = 10000 }
        agc.process(&data)
        #expect(data.allSatisfy { $0.isFinite })
    }

    @Test func resetClearsDelayLine() {
        let agc = makeAgc(enabled: true)
        var hot = [Float](repeating: 10000, count: 2048)
        agc.process(&hot)
        agc.reset()
        var cold = [Float](repeating: 0, count: 2048)
        agc.process(&cold)
        #expect(cold.allSatisfy { abs($0) < 1 })
    }
}

// MARK: - test_blackman_harris.cpp

@Suite struct BlackmanHarrisTests {
    @Test func emptyOnZeroLength() {
        #expect(blackmanHarrisStep(0).isEmpty)
    }

    @Test func endsAtOne() {
        #expect(blackmanHarrisStep(149).last == 1.0)
    }

    @Test func startsNearZero() {
        let r = blackmanHarrisStep(149)
        #expect(r[0] < 0.01)
        #expect(r[0] >= 0)
    }

    @Test func monotonicallyIncreasing() {
        let r = blackmanHarrisStep(149)
        for i in 1..<r.count {
            #expect(r[i] >= r[i - 1], "non-monotone at index \(i)")
        }
    }

    @Test func riseTimeMatchesDefault() {
        #expect(blackmanHarrisStep(149).count == 149)
    }
}

// MARK: - test_modulator.cpp

@Suite struct ModulatorTests {
    @Test func tableHasIntegerPeriodCount() {
        // SR=11025, carrier=600 → table length = round(11025/600) = 18.
        #expect(Modulator(sampleRate: sr, carrierFreq: 600).tableSize == 18)
    }

    @Test func pitch450RoundsHalfToEven() {
        // 11025 / 450 = 24.5 exactly → Delphi Round gives 24.
        #expect(Modulator(sampleRate: sr, carrierFreq: 450).tableSize == 24)
    }

    @Test func zeroInputProducesZeroOutput() {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        let input = ComplexBuf(count: 64)
        var out = [Float](repeating: 99, count: 64)
        m.modulate(input, &out)
        #expect(out.allSatisfy { $0 == 0 })
    }

    @Test func constantInputProducesPeriodicTone() {
        // re=1, im=0 → sin(φ); RMS over whole periods ≈ sqrt(1/2).
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        let n = 64 * m.tableSize
        var input = ComplexBuf(count: n)
        for i in 0..<n { input.re[i] = 1 }
        var out = [Float](repeating: 0, count: n)
        m.modulate(input, &out)
        let sumSq = out.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = (sumSq / Double(n)).squareRoot()
        #expect(abs(rms - 0.5.squareRoot()) <= 1.0e-5)
    }

    @Test func perfectQuadratureInputIsBounded() {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        let n = m.tableSize * 32
        var input = ComplexBuf(count: n)
        let step = 2.0 * MathK.pi / Double(m.tableSize)
        for i in 0..<n {
            input.re[i] = Float(sin(step * Double(i)))
            input.im[i] = Float(cos(step * Double(i)))
        }
        var out = [Float](repeating: 0, count: n)
        m.modulate(input, &out)
        #expect(out.allSatisfy { abs($0) <= 1.001 })
    }

    @Test func resetReturnsToPhaseZero() {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        var input = ComplexBuf(count: 32)
        input.re[5] = 1
        var out = [Float](repeating: 0, count: 32)
        m.modulate(input, &out)
        m.reset()
        let m2 = Modulator(sampleRate: sr, carrierFreq: 600)
        var out2 = [Float](repeating: 0, count: 32)
        m.modulate(input, &out)
        m2.modulate(input, &out2)
        #expect(out == out2)
    }
}

// MARK: - test_morse_keyer.cpp

@Suite struct MorseKeyerTests {
    @Test func samplesPerUnitAtDefault() {
        #expect(MorseKeyer(sampleRate: sr, wpm: 30).samplesPerUnit == 441)
    }

    @Test func rampLengthAtDefault() {
        #expect(MorseKeyer(sampleRate: sr, wpm: 30).rampSamples == 149)
    }

    @Test func envelopeLengthMatchesUnits() {
        // ".~" = 3 units → 3·441 + 149.
        #expect(MorseKeyer(sampleRate: sr, wpm: 30).renderEnvelope("E").count == 3 * 441 + 149)
    }

    @Test func envelopeStartsRampsAndPeaks() {
        let env = MorseKeyer(sampleRate: sr, wpm: 30).renderEnvelope("E")
        #expect(!env.isEmpty)
        #expect(env[0] < 1.0e-3)
        #expect(env[0] >= 0)
        #expect(env.max() == 1.0)
    }

    @Test func rangeIsZeroToOne() {
        let env = MorseKeyer(sampleRate: sr, wpm: 30).renderEnvelope("CQ TEST")
        #expect(env.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func wpmChangesSampleCount() {
        let k = MorseKeyer(sampleRate: sr, wpm: 30)
        let at30 = k.renderEnvelope("PARIS").count
        k.setWpm(60)
        let at60 = k.renderEnvelope("PARIS").count
        #expect(at60 < at30)
    }

    @Test func emptyMessageReturnsEmpty() {
        #expect(MorseKeyer(sampleRate: sr, wpm: 30).renderEnvelope("").isEmpty)
    }

    // Delphi Round() rounds exact halves to even. 13230 / WPM is an exact
    // .5 at 12, 28 and 60 WPM; Pascal gets 1102 / 472 / 220.
    @Test func samplesPerUnitUsesDelphiRounding() {
        #expect(MorseKeyer(sampleRate: sr, wpm: 12).samplesPerUnit == 1102)
        #expect(MorseKeyer(sampleRate: sr, wpm: 28).samplesPerUnit == 472)
        #expect(MorseKeyer(sampleRate: sr, wpm: 60).samplesPerUnit == 220)
    }

    // Above ~88 WPM a unit is shorter than the 149-sample ramp; Pascal's
    // signed write pointer moves backwards and ramps overlap.
    @Test func highSpeedEnvelopeStaysInBounds() {
        for wpm in 85...120 {
            let env = MorseKeyer(sampleRate: sr, wpm: wpm)
                .renderEnvelope("HHHHH 55555 CQ TEST VE3NEA")
            #expect(!env.isEmpty, "wpm \(wpm)")
            #expect((env.max() ?? 0) > 0.5, "wpm \(wpm)")
            #expect(env.allSatisfy { $0 >= 0 && $0 <= 1 }, "wpm \(wpm)")
        }
    }
}

// MARK: - test_morse_table.cpp

@Suite struct MorseTableTests {
    @Test func knownLetters() {
        #expect(MorseTable.pattern(for: "E") == ".")
        #expect(MorseTable.pattern(for: "T") == "-")
        #expect(MorseTable.pattern(for: "A") == ".-")
        #expect(MorseTable.pattern(for: "N") == "-.")
        #expect(MorseTable.pattern(for: "Q") == "--.-")
    }

    @Test func caseInsensitive() {
        #expect(MorseTable.pattern(for: "q") == MorseTable.pattern(for: "Q"))
        #expect(MorseTable.pattern(for: "a") == MorseTable.pattern(for: "A"))
    }

    @Test func digits() {
        #expect(MorseTable.pattern(for: "0") == "-----")
        #expect(MorseTable.pattern(for: "5") == ".....")
        #expect(MorseTable.pattern(for: "9") == "----.")
    }

    @Test func punctuation() {
        #expect(MorseTable.pattern(for: "/") == "-..-.")
        #expect(MorseTable.pattern(for: ".") == ".-.-.-")
        #expect(MorseTable.pattern(for: "?") == "..--..")
    }

    @Test func unknownReturnsEmpty() {
        #expect(MorseTable.pattern(for: "@").isEmpty)
        #expect(MorseTable.pattern(for: "!").isEmpty)
    }

    @Test func prosigns() {
        #expect(MorseTable.prosign("SK") == "...-.-")
        #expect(MorseTable.prosign("AR") == ".-.-.")
        #expect(MorseTable.prosign("ar") == MorseTable.prosign("AR"))
        #expect(MorseTable.prosign("XX").isEmpty)
    }

    @Test func encodeMessageCq() {
        #expect(encodeMessage("CQ") == "-.-. --.-~")
    }

    @Test func encodeMessageWithSpace() {
        #expect(encodeMessage("E T") == ".  -~")
    }

    @Test func encodeIgnoresUnknown() {
        #expect(encodeMessage("E@T") == encodeMessage("ET"))
    }

    @Test func encodeEmpty() {
        #expect(encodeMessage("").isEmpty)
    }
}

// MARK: - test_moving_average.cpp

@Suite struct MovingAverageTests {
    private let points = 16
    private let passes = 3
    private let block = 64

    private func make() -> MovingAverage {
        let m = MovingAverage()
        m.configure(points: points, passes: passes, samplesInInput: block, gainDb: 0)
        return m
    }

    @Test func impulseEnergyConservation() {
        let m = make()
        var input = [Float](repeating: 0, count: block)
        input[0] = 1
        var out = [Float](repeating: 0, count: block)
        var total = 0.0
        for _ in 0..<8 {
            m.process(input, &out)
            total += out.reduce(0.0) { $0 + Double($1) }
            input = [Float](repeating: 0, count: block)
        }
        #expect(abs(total - 1.0) <= 1.0e-4)
    }

    @Test func dcResponseEqualsOne() {
        let m = make()
        let input = [Float](repeating: 1, count: block)
        var out = [Float](repeating: 0, count: block)
        for _ in 0..<16 { m.process(input, &out) }
        #expect(out.allSatisfy { abs($0 - 1) <= 1.0e-5 })
    }

    @Test func resetZeroesState() {
        let m = make()
        let ones = [Float](repeating: 1, count: block)
        var out = [Float](repeating: 0, count: block)
        for _ in 0..<4 { m.process(ones, &out) }
        m.reset()
        m.process([Float](repeating: 0, count: block), &out)
        #expect(out.allSatisfy { $0 == 0 })
    }

    @Test func complexProcessesReAndImIndependently() {
        let m = make()
        var buf = ComplexBuf(count: block)
        buf.re[0] = 1
        m.processComplex(&buf)
        #expect(buf.im.allSatisfy { $0 == 0 })
    }

    @Test func inPlaceMatchesSeparateBuffers() {
        let a = make()
        let b = make()
        let input = (0..<block).map { Float($0 % 7) - 3 }
        var out = [Float](repeating: 0, count: block)
        a.process(input, &out)
        var data = input
        b.process(&data)
        #expect(data == out)
    }
}

// MARK: - test_ping_pong_filter.cpp

@Suite struct PingPongFilterTests {
    private func dcBuf() -> ComplexBuf {
        ComplexBuf(re: [Float](repeating: 1, count: 64), im: [Float](repeating: 1, count: 64))
    }

    @Test func configureZeroesBlockCount() {
        let p = PingPongFilter()
        p.configure(points: 16, passes: 3, samplesInInput: 64, gainDb: 0)
        #expect(p.blockCount == 0)
    }

    @Test func processIncrementsBlockCount() {
        let p = PingPongFilter()
        p.configure(points: 16, passes: 3, samplesInInput: 64, gainDb: 0)
        var buf = dcBuf()
        p.process(&buf)
        #expect(p.blockCount == 1)
        p.process(&buf)
        #expect(p.blockCount == 2)
    }

    @Test func noAudibleDiscontinuityAtSwap() {
        let p = PingPongFilter()
        p.configure(points: 16, passes: 3, samplesInInput: 64, gainDb: 0)
        var buf = dcBuf()
        for _ in 0..<(AudioK.filterSwapBlocks - 1) {
            buf = dcBuf()
            p.process(&buf)
        }
        buf = dcBuf()
        p.process(&buf)
        let lastBefore = buf.re[buf.re.count - 1]
        buf = dcBuf()
        p.process(&buf)
        let firstAfter = buf.re[0]
        #expect(abs(lastBefore - 1) <= 0.05)
        #expect(abs(firstAfter - 1) <= 0.05)
    }
}

// MARK: - test_qsb.cpp

@Suite struct QsbTests {
    @Test func applyIsFiniteAndBounded() {
        let q = Qsb(bufSize: 512, rng: Random(seed: 42))
        q.setBandwidth(0.2)
        var sig = [Float](repeating: 1, count: 2048)
        q.applyTo(&sig)
        #expect(sig.allSatisfy { $0.isFinite && abs($0) < 50 })
    }

    @Test func nonZeroVariance() {
        let q = Qsb(bufSize: 512, rng: Random(seed: 7))
        q.setBandwidth(0.2)
        var sig = [Float](repeating: 1, count: 4096)
        q.applyTo(&sig)
        let mean = sig.reduce(0.0) { $0 + Double($1) } / Double(sig.count)
        let v = sig.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / Double(sig.count)
        #expect(v > 0)
    }

    @Test func flutterBandwidthAccepted() {
        let q = Qsb(bufSize: 512, rng: Random(seed: 1))
        q.setBandwidth(15)
        #expect(q.bandwidth == 15)
    }
}

// MARK: - test_quick_average.cpp

@Suite struct QuickAverageTests {
    @Test func defaultsMatchPascal() {
        let q = QuickAverage()
        #expect(q.points == 128)
        #expect(q.passes == 4)
    }

    @Test func zeroInputProducesZeroOutput() {
        let q = QuickAverage()
        q.setPoints(16)
        q.setPasses(2)
        for _ in 0..<200 {
            #expect(q.filter(0) == 0)
        }
    }

    @Test func dcInputConvergesToOne() {
        let q = QuickAverage()
        q.setPoints(16)
        q.setPasses(2)
        var last: Float = 0
        for _ in 0..<4096 { last = q.filter(1) }
        #expect(abs(last - 1) <= 1.0e-3)
    }

    @Test func passesClampedTo8() {
        let q = QuickAverage()
        q.setPasses(20)
        #expect(q.passes <= 8)
    }
}

// MARK: - ComplexBuf

@Suite struct ComplexBufTests {
    @Test func resizeKeepsPrefixAndClearZeroes() {
        var b = ComplexBuf(re: [1, 2, 3], im: [4, 5, 6])
        b.resize(5)
        #expect(b.re == [1, 2, 3, 0, 0])
        #expect(b.im == [4, 5, 6, 0, 0])
        b.resize(2)
        #expect(b.size == 2)
        b.clear()
        #expect(b.re == [0, 0])
        #expect(b.im == [0, 0])
    }
}
