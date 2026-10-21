// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MRDSP must reproduce the C++ mr::dsp output bit for bit
// (Fixtures/dsp/, from golden_dsp.cpp, tag cpp-qt-reference). Every comparison is
// on IEEE-754 bit patterns — stricter than `==` (distinguishes -0/+0).

import MRCore
@testable import MRDSP
import MRTestSupport
import Testing

// MARK: - Helpers

private func f(_ bits: UInt32) -> Float { Float(bitPattern: bits) }

/// Exact (bitwise) equality; on mismatch records the first differing
/// index so a failure is diagnosable.
private func expectExact(_ got: [Float], _ want: [Float], _ label: String,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(got.count == want.count, "\(label): count \(got.count) vs \(want.count)",
            sourceLocation: sourceLocation)
    let n = min(got.count, want.count)
    for i in 0..<n where got[i].bitPattern != want[i].bitPattern {
        Issue.record("\(label): first mismatch at [\(i)]: \(got[i]) vs \(want[i])",
                     sourceLocation: sourceLocation)
        return
    }
}

/// The shared input signals, loaded once; each test unwraps them with
/// `try`, so a missing fixture fails the test instead of yielding [].
private enum Signals {
    static let re = Result { try Fixtures.floats("dsp/signal_re.f32") }
    static let im = Result { try Fixtures.floats("dsp/signal_im.f32") }
    static let agc = Result { try Fixtures.floats("dsp/agc_input.f32") }
}

/// Decodes a fixture's case list for `@Test(arguments:)`.
private func cases<T: Decodable>(_ type: [T].Type, _ path: String) throws -> [T] {
    try Fixtures.json(type, path)
}

@Test func sharedSignalsLoaded() throws {
    #expect(try Signals.re.get().count == 65536)
    #expect(try Signals.im.get().count == 65536)
    #expect(try Signals.agc.get().count == 65536)
}

/// Every case file is present and non-empty (the parameterized tests
/// below would silently run zero cases otherwise).
@Test(arguments: ["dsp/bh.json", "dsp/keyer.json", "dsp/movavg.json", "dsp/pingpong.json",
                  "dsp/quickavg.json", "dsp/qsb.json", "dsp/modulator.json", "dsp/agc.json"])
func caseListsArePresent(_ path: String) throws {
    let list = try Fixtures.json([AnyCase].self, path)
    #expect(!list.isEmpty)
}

private struct AnyCase: Decodable {
    init(from decoder: any Decoder) throws {}
}

// MARK: - Blackman-Harris

@Test(arguments: try cases([Int].self, "dsp/bh.json"))
func blackmanHarrisMatchesCpp(len: Int) throws {
    let want = try Fixtures.floats("dsp/bh/\(len).f32")
    expectExact(blackmanHarrisStep(len), want, "bh len \(len)")
}

// MARK: - MorseKeyer

private struct KeyerCase: Decodable, CustomTestStringConvertible {
    let text: String
    let sr: Int
    let wpm: Int
    let viaSetters: Bool
    let samplesPerUnit: Int
    let rampSamples: Int
    let count: Int
    let file: String
    var testDescription: String { "\"\(text)\" sr \(sr) wpm \(wpm)\(viaSetters ? " (setters)" : "")" }
}

@Test(arguments: try cases([KeyerCase].self, "dsp/keyer.json"))
private func morseKeyerMatchesCpp(_ c: KeyerCase) throws {
    do {
        let k: MorseKeyer
        if c.viaSetters {
            k = MorseKeyer(sampleRate: AudioK.sampleRate, wpm: 30)
            k.setSampleRate(c.sr)
            k.setWpm(c.wpm)
        } else {
            k = MorseKeyer(sampleRate: c.sr, wpm: c.wpm)
        }
        let label = "keyer \"\(c.text)\" sr \(c.sr) wpm \(c.wpm)"
        #expect(k.samplesPerUnit == c.samplesPerUnit, "\(label)")
        #expect(k.rampSamples == c.rampSamples, "\(label)")
        let env = k.renderEnvelope(c.text)
        #expect(env.count == c.count, "\(label)")
        expectExact(env, try Fixtures.floats("dsp/keyer/\(c.file)"), label)
    }
}

// MARK: - MovingAverage

private struct MovAvgCase: Decodable, CustomTestStringConvertible {
    let points: Int
    let passes: Int
    let block: Int
    let gainDbBits: UInt32
    let inLen: Int
    let blocks: Int
    let complex: Bool
    let file: String
    var testDescription: String { "\(file): pts \(points) block \(block) in \(inLen)" }
}

@Test(arguments: try cases([MovAvgCase].self, "dsp/movavg.json"))
private func movingAverageMatchesCpp(_ c: MovAvgCase) throws {
    let signalRe = try Signals.re.get()
    let signalIm = try Signals.im.get()
    do {
        let m = MovingAverage()
        m.configure(points: c.points, passes: c.passes, samplesInInput: c.block,
                    gainDb: f(c.gainDbBits))
        var outAll: [Float] = []
        var off = 0
        for _ in 0..<c.blocks {
            let inRe = Array(signalRe[off..<(off + c.inLen)])
            if c.complex {
                var buf = ComplexBuf(re: inRe, im: Array(signalIm[off..<(off + c.inLen)]))
                m.processComplex(&buf)
                outAll += buf.re
                outAll += buf.im
            } else {
                var out = [Float](repeating: -7.0, count: c.inLen)
                m.process(inRe, &out)
                outAll += out
            }
            off += c.inLen
        }
        expectExact(outAll, try Fixtures.floats("dsp/movavg/\(c.file)"),
                    "movavg \(c.testDescription)")
    }
}

@Test func movingAverageSettersMatchCpp() throws {
    let signalRe = try Signals.re.get()
    let m = MovingAverage()
    m.configure(points: 32, passes: 3, samplesInInput: 64, gainDb: 0)
    var outAll: [Float] = []
    var off = 0
    func run(_ n: Int) {
        for _ in 0..<n {
            let len = m.samplesInInput
            var out = [Float](repeating: 0, count: len)
            m.process(Array(signalRe[off..<(off + len)]), &out)
            outAll += out
            off += len
        }
    }
    run(3)
    m.setGainDb(4.0)
    run(3)
    m.setPoints(20)
    run(3)
    m.setPasses(2)
    run(3)
    m.setSamplesInInput(48)
    run(3)
    m.setPoints(20)
    m.reset()
    run(2)
    expectExact(outAll, try Fixtures.floats("dsp/movavg/setters.f32"), "movavg setters")
}

// MARK: - PingPongFilter

private struct PingPongCase: Decodable, CustomTestStringConvertible {
    let bw: Int
    let points: Int
    let gainDbBits: UInt32
    let block: Int
    let blocks: Int
    let resetAt: Int
    let blockCounts: [Int]
    let file: String
    var testDescription: String { "bw \(bw) block \(block)" }
}

@Test(arguments: try cases([PingPongCase].self, "dsp/pingpong.json"))
private func pingPongFilterMatchesCpp(_ c: PingPongCase) throws {
    let signalRe = try Signals.re.get()
    let signalIm = try Signals.im.get()
    do {
        // The Contest's bandwidth → filter mapping, recomputed in Swift.
        let bw = Float(c.bw)
        let points = max(1, delphiRound(DspK.filterPointsRatio * Float(AudioK.sampleRate) / bw))
        #expect(points == c.points)
        let p = PingPongFilter()
        p.configure(points: points, passes: DspK.filterPasses, samplesInInput: c.block,
                    gainDb: f(c.gainDbBits))
        var outAll: [Float] = []
        var counts: [Int] = []
        var off = 0
        for b in 0..<c.blocks {
            if b == c.resetAt { p.reset() }
            var buf = ComplexBuf(re: Array(signalRe[off..<(off + c.block)]),
                                 im: Array(signalIm[off..<(off + c.block)]))
            p.process(&buf)
            outAll += buf.re
            outAll += buf.im
            counts.append(Int(p.blockCount))
            off += c.block
        }
        #expect(counts == c.blockCounts)
        expectExact(outAll, try Fixtures.floats("dsp/pingpong/\(c.file)"),
                    "pingpong bw \(c.bw) block \(c.block)")
    }
}

// MARK: - QuickAverage

private struct QuickAvgCase: Decodable, CustomTestStringConvertible {
    let points: Int
    let passes: Int
    let n: Int
    let pointsAfter: Int
    let passesAfter: Int
    let file: String
    var testDescription: String { "\(points)x\(passes)" }
}

@Test(arguments: try cases([QuickAvgCase].self, "dsp/quickavg.json"))
private func quickAverageMatchesCpp(_ c: QuickAvgCase) throws {
    let signalRe = try Signals.re.get()
    let signalIm = try Signals.im.get()
    do {
        let q = QuickAverage()
        if !(c.points == 128 && c.passes == 4) {
            q.setPasses(c.passes)
            q.setPoints(c.points)
        }
        #expect(q.points == c.pointsAfter)
        #expect(q.passes == c.passesAfter)
        let real = (0..<c.n).map { q.filter(signalRe[$0] * 0.001) }
        q.reset()
        var cplx: [Float] = []
        for i in 0..<c.n {
            let r = q.filterComplex(signalRe[i], signalIm[i])
            cplx.append(r.re)
            cplx.append(r.im)
        }
        let mod = (0..<c.n).map { q.filteredModule(signalIm[$0] * 0.01, signalRe[$0] * 0.01) }
        let label = "quickavg \(c.points)x\(c.passes)"
        expectExact(real, try Fixtures.floats("dsp/quickavg/\(c.file)_real.f32"), label + " real")
        expectExact(cplx, try Fixtures.floats("dsp/quickavg/\(c.file)_complex.f32"), label + " complex")
        expectExact(mod, try Fixtures.floats("dsp/quickavg/\(c.file)_module.f32"), label + " module")
    }
}

// MARK: - Qsb

private struct QsbCase: Decodable, CustomTestStringConvertible {
    let seed: UInt64
    let bufSize: Int
    let bwBits: UInt32
    let bandwidthBits: UInt32
    let arrLen: Int
    let blocks: Int
    let ones: Bool
    let nextUniformBits: UInt32
    let file: String
    var testDescription: String { "seed \(seed) buf \(bufSize) \(file)" }
}

@Test(arguments: try cases([QsbCase].self, "dsp/qsb.json"))
private func qsbMatchesCpp(_ c: QsbCase) throws {
    let signalRe = try Signals.re.get()
    do {
        let rng = Random(seed: c.seed)
        let q = Qsb(bufSize: c.bufSize, rng: rng)
        q.setBandwidth(f(c.bwBits))
        #expect(q.bandwidth.bitPattern == c.bandwidthBits)
        var outAll: [Float] = []
        var off = 0
        for _ in 0..<c.blocks {
            var arr: [Float]
            if c.ones {
                arr = [Float](repeating: 1.0, count: c.arrLen)
            } else {
                arr = Array(signalRe[off..<(off + c.arrLen)])
                off += c.arrLen
            }
            q.applyTo(&arr)
            outAll += arr
        }
        // Same number of draws consumed as the C++.
        #expect(rng.uniform01().bitPattern == c.nextUniformBits, "qsb seed \(c.seed) rng state")
        expectExact(outAll, try Fixtures.floats("dsp/qsb/\(c.file)"),
                    "qsb seed \(c.seed) bw \(f(c.bwBits)) buf \(c.bufSize)")
    }
}

// MARK: - Modulator

private struct ModulatorCase: Decodable, CustomTestStringConvertible {
    let sr: Int
    let pitchBits: UInt32
    let pitch2Bits: UInt32
    let block: Int
    let blocks: Int
    let switchAt: Int
    let tableSizes: [Int]
    let carrierFreqBits: [UInt32]
    let file: String
    var testDescription: String { "sr \(sr) \(file)" }
}

@Test(arguments: try cases([ModulatorCase].self, "dsp/modulator.json"))
private func modulatorMatchesCpp(_ c: ModulatorCase) throws {
    let signalRe = try Signals.re.get()
    let signalIm = try Signals.im.get()
    do {
        let m = Modulator(sampleRate: c.sr, carrierFreq: f(c.pitchBits))
        var outAll: [Float] = []
        var sizes: [Int] = []
        var freqs: [UInt32] = []
        var off = 0
        for b in 0..<c.blocks {
            if b == c.switchAt { m.setCarrierFreq(f(c.pitch2Bits)) }
            let buf = ComplexBuf(re: Array(signalRe[off..<(off + c.block)]),
                                 im: Array(signalIm[off..<(off + c.block)]))
            var out = [Float](repeating: 0, count: c.block)
            m.modulate(buf, &out)
            outAll += out
            sizes.append(m.tableSize)
            freqs.append(m.carrierFreq.bitPattern)
            off += c.block
        }
        // Unit inputs expose the sin and cos tables directly.
        m.reset()
        var unit = ComplexBuf(count: m.tableSize)
        for i in 0..<unit.size { unit.re[i] = 1.0 }
        var sn = [Float](repeating: 0, count: unit.size)
        m.modulate(unit, &sn)
        m.reset()
        for i in 0..<unit.size {
            unit.re[i] = 0.0
            unit.im[i] = -1.0
        }
        var cs = [Float](repeating: 0, count: unit.size)
        m.modulate(unit, &cs)
        outAll += sn
        outAll += cs

        let label = "modulator sr \(c.sr) pitch \(f(c.pitchBits))"
        #expect(sizes == c.tableSizes, "\(label)")
        #expect(freqs == c.carrierFreqBits, "\(label)")
        expectExact(outAll, try Fixtures.floats("dsp/modulator/\(c.file)"), label)
    }
}

// MARK: - Agc

private struct AgcCase: Decodable, CustomTestStringConvertible {
    let contest: Bool
    let noiseInDbBits: UInt32
    let noiseOutDbBits: UInt32
    let maxOutBits: UInt32
    let attack: Int
    let hold: Int
    let enabled: Bool
    let block: Int
    let blocks: Int
    let resetAt: Int
    let inScaleBits: UInt32
    let overload: [Int]
    let maxOutAfterBits: UInt32
    let file: String
    var testDescription: String { "agc \(file)" }
}

@Test(arguments: try cases([AgcCase].self, "dsp/agc.json"))
private func agcMatchesCpp(_ c: AgcCase) throws {
    let agcInput = try Signals.agc.get()
    do {
        let a = Agc()
        if c.contest {
            a.setMaxOut(f(c.maxOutBits))
            a.setNoiseInDb(f(c.noiseInDbBits))
            a.setNoiseOutDb(f(c.noiseOutDbBits))
            a.setAttackSamples(c.attack)
            a.setHoldSamples(c.hold)
            a.setEnabled(c.enabled)
        }
        let scale = f(c.inScaleBits)
        var outAll: [Float] = []
        var overload: [Int] = []
        var off = 0
        for b in 0..<c.blocks {
            if b == c.resetAt { a.reset() }
            var data = (0..<c.block).map { agcInput[(off + $0) % agcInput.count] * scale }
            a.process(&data)
            outAll += data
            overload.append(a.isOverload ? 1 : 0)
            off += c.block
        }
        #expect(overload == c.overload, "\(c.testDescription) overload flags")
        #expect(a.maxOut.bitPattern == c.maxOutAfterBits)
        expectExact(outAll, try Fixtures.floats("dsp/agc/\(c.file)"), c.testDescription)
    }
}
