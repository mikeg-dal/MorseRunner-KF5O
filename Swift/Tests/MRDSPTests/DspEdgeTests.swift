// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Edge cases and guards of the MRDSP API: initializer preconditions,
// setter guards, the ComplexBuf length invariant, odd block sizes.

import Darwin
import MRCore
@testable import MRDSP
import Testing

private let sr = AudioK.sampleRate

// MARK: - MorseTable.encode

@Suite struct MorseEncodeTests {
    @Test(arguments: [
        ("CQ", "-.-. --.-~"),
        ("cq", "-.-. --.-~"),                 // case-insensitive
        ("E_T", ".  -~"),                     // '_' is a gap like ' '
        ("E  T", ".   -~"),                   // each blank is one gap
        ("E@T", ". -~"),                      // unknown dropped
        ("E\u{E9}T", ". -~"),                 // non-ASCII bytes dropped
        ("@#!", ""),                          // nothing encodable: no '~'
        (" ", "~"),                           // a lone gap becomes the marker
        ("", ""),
        ("5NN", "..... -. -.~"),
        ("/?", "-..-. ..--..~"),
    ])
    func encode(_ text: String, _ want: String) {
        #expect(MorseTable.encode(text) == want)
        #expect(encodeMessage(text) == want)
    }

    @Test func everySingleCharacterKeyEncodesToItsPattern() {
        for e in MorseTable.entries where e.key.utf8.count == 1 {
            #expect(MorseTable.encode(e.key) == e.pattern + "~", "\(e.key)")
        }
    }

    @Test func prosignLookupIsAsciiCaseInsensitive() {
        #expect(MorseTable.prosign("Sk") == "...-.-")
        #expect(MorseTable.prosign("dx") == "-..-..-")
        #expect(MorseTable.prosign("\u{DF}") == "")   // "ß" must not fold to "SS"
        #expect(MorseTable.prosign("") == "")
    }

    @Test func patternForNonAsciiIsEmpty() {
        #expect(MorseTable.pattern(for: "\u{E9}").isEmpty)
        #expect(MorseTable.pattern(for: "\u{212A}").isEmpty)   // Kelvin sign, uppercases to "K" in Unicode
    }
}

// MARK: - MorseKeyer

@Suite struct MorseKeyerGuardTests {
    @Test func setSampleRateRecomputesTimingAndRamps() {
        let k = MorseKeyer(sampleRate: sr, wpm: 30)
        k.setSampleRate(8000)
        #expect(k.samplesPerUnit == delphiRound(0.1 * 8000.0 * 12.0 / 30.0))   // 320
        #expect(k.rampSamples == delphiRound(2.7 * 0.005 * 8000.0))            // 108
        let fresh = MorseKeyer(sampleRate: 8000, wpm: 30)
        #expect(k.renderEnvelope("TEST") == fresh.renderEnvelope("TEST"))
    }

    @Test(arguments: [0, -1, -11025])
    func setSampleRateIgnoresNonPositive(_ rate: Int) {
        let k = MorseKeyer(sampleRate: sr, wpm: 30)
        k.setSampleRate(rate)
        #expect(k.samplesPerUnit == 441)
        #expect(k.rampSamples == 149)
    }

    @Test(arguments: [0, -5])
    func setWpmIgnoresNonPositive(_ wpm: Int) {
        let k = MorseKeyer(sampleRate: sr, wpm: 30)
        k.setWpm(wpm)
        #expect(k.samplesPerUnit == 441)
    }

    @Test func zeroWpmInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = MorseKeyer(sampleRate: 11025, wpm: 0) }
    }

    @Test func negativeWpmInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = MorseKeyer(sampleRate: 11025, wpm: -30) }
    }

    @Test func zeroSampleRateInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = MorseKeyer(sampleRate: 0, wpm: 30) }
    }
}

// MARK: - Modulator

@Suite struct ModulatorGuardTests {
    @Test(arguments: [Float(0), -600, -.infinity, .nan])
    func setCarrierFreqIgnoresInvalid(_ hz: Float) {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        m.setCarrierFreq(hz)
        #expect(m.tableSize == 18)
        #expect(m.carrierFreq == Float(sr) / 18)
    }

    @Test func setSampleRateRebuildsTable() {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        m.setSampleRate(8000)
        #expect(m.sampleRate == 8000)
        #expect(m.tableSize == delphiRound(8000.0 / Double(Float(11025) / 18)))
        m.setSampleRate(0)                     // ignored
        #expect(m.sampleRate == 8000)
    }

    @Test func zeroCarrierInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = Modulator(sampleRate: 11025, carrierFreq: 0) }
    }

    @Test func nanCarrierInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = Modulator(sampleRate: 11025, carrierFreq: .nan) }
    }

    @Test func zeroSampleRateInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = Modulator(sampleRate: 0, carrierFreq: 600) }
    }

    @Test func outputShorterThanInputWritesOnlyOutput() {
        let m = Modulator(sampleRate: sr, carrierFreq: 600)
        var input = ComplexBuf(count: 40)
        for i in 0..<40 { input.re[i] = 1 }
        var short = [Float](repeating: 0, count: 10)
        m.modulate(input, &short)
        m.reset()
        var long = [Float](repeating: 0, count: 40)
        m.modulate(input, &long)
        #expect(short == Array(long[0..<10]))
    }

    @Test func phaseContinuesAcrossBlocksAndWraps() {
        // Odd block lengths straddle the 18-entry table boundary.
        let a = Modulator(sampleRate: sr, carrierFreq: 600)
        let b = Modulator(sampleRate: sr, carrierFreq: 600)
        var input = ComplexBuf(count: 100)
        for i in 0..<100 {
            input.re[i] = Float(i)
            input.im[i] = Float(100 - i)
        }
        var whole = [Float](repeating: 0, count: 100)
        a.modulate(input, &whole)
        var pieces: [Float] = []
        var off = 0
        for len in [7, 18, 1, 35, 39] {
            let part = ComplexBuf(re: Array(input.re[off..<(off + len)]),
                                  im: Array(input.im[off..<(off + len)]))
            var out = [Float](repeating: 0, count: len)
            b.modulate(part, &out)
            pieces += out
            off += len
        }
        #expect(pieces == whole)
    }
}

// MARK: - ComplexBuf invariant

@Suite struct ComplexBufInvariantTests {
    @Test func everyInitializerKeepsLengthsEqual() {
        #expect(ComplexBuf().isConsistent)
        #expect(ComplexBuf(count: 7).isConsistent)
        #expect(ComplexBuf(re: [1, 2], im: [3, 4]).isConsistent)
        var b = ComplexBuf(count: 3)
        b.resize(9)
        #expect(b.isConsistent && b.size == 9)
        b.resize(0)
        #expect(b.isConsistent && b.size == 0)
        b.clear()
        #expect(b.isConsistent)
    }

    @Test func mismatchedInitTraps() async {
        await #expect(processExitsWith: .failure) { _ = ComplexBuf(re: [1, 2, 3], im: [1]) }
    }

    @Test func modulateRejectsMismatchedBuffer() async {
        await #expect(processExitsWith: .failure) {
            var buf = ComplexBuf(count: 8)
            buf.im.removeLast(4)
            var out = [Float](repeating: 0, count: 8)
            Modulator(sampleRate: 11025, carrierFreq: 600).modulate(buf, &out)
        }
    }

    @Test func pingPongRejectsMismatchedBuffer() async {
        await #expect(processExitsWith: .failure) {
            let p = PingPongFilter()
            p.configure(points: 16, passes: 3, samplesInInput: 64, gainDb: 0)
            var buf = ComplexBuf(count: 64)
            buf.re.append(0)
            p.process(&buf)
        }
    }
}

// MARK: - PingPongFilter with other block sizes

@Suite struct PingPongBlockSizeTests {
    private func input(_ n: Int, _ phase: Int) -> ComplexBuf {
        ComplexBuf(re: (0..<n).map { Float(($0 + phase) % 13) - 6 },
                   im: (0..<n).map { Float(($0 * 3 + phase) % 7) - 3 })
    }

    /// The first block comes from filter A alone, so it must equal a lone
    /// MovingAverage fed the same input — for any block length, including
    /// ones that differ from samplesInInput (only the first samplesInInput
    /// outputs are written; the rest of the buffer is left as it was).
    @Test(arguments: [16, 63, 64, 65, 100, 300])
    func firstBlockMatchesSingleFilter(_ n: Int) {
        let block = 64
        let p = PingPongFilter()
        p.configure(points: 16, passes: 3, samplesInInput: block, gainDb: 0)
        let ref = MovingAverage()
        ref.configure(points: 16, passes: 3, samplesInInput: block, gainDb: 0)

        var buf = input(n, 0)
        var want = buf
        p.process(&buf)
        ref.processComplex(&want)
        #expect(buf == want)
        #expect(buf.isConsistent && buf.size == n)
        #expect(p.blockCount == 1)
        if n > block {
            let original = input(n, 0)
            #expect(Array(buf.re[block...]) == Array(original.re[block...]))
        }
    }

    @Test(arguments: [32, 100])
    func manyBlocksStayFiniteAcrossSwaps(_ n: Int) {
        let p = PingPongFilter()
        p.configure(points: 16, passes: 3, samplesInInput: 64, gainDb: 0)
        for b in 0..<(3 * AudioK.filterSwapBlocks + 1) {
            var buf = input(n, b)
            p.process(&buf)
            #expect(buf.re.allSatisfy(\.isFinite) && buf.im.allSatisfy(\.isFinite))
        }
        #expect(p.blockCount == UInt64(3 * AudioK.filterSwapBlocks + 1))
    }
}

// MARK: - Qsb with tiny buffers

@Suite struct QsbSmallBufferTests {
    @Test(arguments: [0, 1, 2, 3])
    func belowFourUsesSingleSampleGroups(_ bufSize: Int) {
        let q = Qsb(bufSize: bufSize, rng: Random(seed: 5))
        var sig = [Float](repeating: 1, count: 9)
        q.applyTo(&sig)
        // Every sample is in a whole 1-sample group, so every one is scaled.
        #expect(sig.allSatisfy { $0.isFinite && $0 != 1 })
    }

    @Test func sameDrawsAsBufSizeFourGroupOfOne() {
        // bufSize 0...7 all give 1-sample groups; their output and draw
        // count must be identical.
        let ra = Random(seed: 77)
        let rb = Random(seed: 77)
        let a = Qsb(bufSize: 2, rng: ra)
        let b = Qsb(bufSize: 7, rng: rb)
        var x = [Float](repeating: 1, count: 33)
        var y = x
        a.applyTo(&x)
        b.applyTo(&y)
        #expect(x == y)
        #expect(ra.nextUInt32() == rb.nextUInt32())
    }

    @Test(arguments: [Float(0), -1, .nan, -.infinity])
    func nonPositiveBandwidthIgnored(_ bw: Float) {
        let q = Qsb(bufSize: 512, rng: Random(seed: 1))
        q.setBandwidth(bw)
        #expect(q.bandwidth == 0.1)
    }
}

// MARK: - Agc constants

@Test func agcEnvelopeFloorLogIsLogOfFloor() {
    #expect(log(Agc.envelopeFloor).bitPattern == Agc.envelopeFloorLog.bitPattern)
}
