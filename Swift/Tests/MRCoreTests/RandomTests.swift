// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MRCore.Random must reproduce the C++ mr::core::Random draw for draw
// (Fixtures/core/random.json, from tools/golden/golden_random.cpp).

import Darwin
@testable import MRCore
import MRTestSupport
import Testing

private struct RandomCase: Decodable, CustomTestStringConvertible {
    let seed: UInt32
    let u32: [UInt32]
    let uniform01: [Float]
    let uniformIntN: [Int]
    let uniformInt: [Int]
    let normal: [Float]
    let gaussLim: [Float]
    let rayleigh: [Float]
    let poissonMeans: [Float]
    let poisson: [Int]
    let uShaped: [Float]

    var testDescription: String { "seed \(seed)" }
}

private func loadCases() throws -> [RandomCase] {
    try Fixtures.json([RandomCase].self, "core/random.json")
}

@Test func fixturesLoaded() throws {
    #expect(try !loadCases().isEmpty)
}

@Test(arguments: try loadCases())
private func matchesCppRandom(_ c: RandomCase) {
    var mt = MT19937(seed: c.seed)
    #expect(c.u32.map { _ in mt.next() } == c.u32)

    let r = Random(seed: UInt64(c.seed))
    #expect(c.uniform01.map { _ in r.uniform01() } == c.uniform01)

    r.reseed(UInt64(c.seed))
    #expect(c.u32.map { _ in r.nextUInt32() } == c.u32)

    r.reseed(UInt64(c.seed))
    var ints: [Int] = []
    for n in c.uniformIntN {
        for _ in 0..<40 { ints.append(r.uniformInt(n)) }
    }
    #expect(ints == c.uniformInt)

    r.reseed(UInt64(c.seed))
    #expect(c.normal.map { _ in r.normal() } == c.normal)

    r.reseed(UInt64(c.seed))
    var gl: [Float] = (0..<100).map { _ in r.gaussLim(0, 300) }
    gl += (0..<100).map { _ in r.gaussLim(20, 10) }
    #expect(gl == c.gaussLim)

    r.reseed(UInt64(c.seed))
    #expect(c.rayleigh.map { _ in r.rayleigh(4) } == c.rayleigh)

    r.reseed(UInt64(c.seed))
    var poi: [Int] = []
    for m in c.poissonMeans {
        for _ in 0..<50 { poi.append(r.poisson(m)) }
    }
    #expect(poi == c.poisson)

    r.reseed(UInt64(c.seed))
    #expect(c.uShaped.map { _ in r.uShaped() } == c.uShaped)
}

// MARK: - MT19937 / Random API

@Suite struct RandomApiTests {
    /// The C++ standard's own conformance value: the 10000th output of a
    /// default-constructed std::mt19937 (seed 5489) is 4123659995. Covers
    /// all 16 twists, including both wrap-around index ranges.
    @Test func mt19937StandardCheckValue() {
        var mt = MT19937(seed: 5489)
        #expect(mt.next() == 3_499_211_612)
        for _ in 1..<9999 { _ = mt.next() }
        #expect(mt.next() == 4_123_659_995)
    }

    @Test func seedGetterReportsConstructorAndReseed() {
        let r = Random(seed: 0x1234_5678_9ABC_DEF0)
        #expect(r.seed == 0x1234_5678_9ABC_DEF0)
        r.reseed(42)
        #expect(r.seed == 42)
    }

    @Test func generatorUsesLow32BitsOfSeed() {
        let a = Random(seed: 0xFFFF_FFFF_0000_0007)
        let b = Random(seed: 7)
        #expect((0..<64).map { _ in a.nextUInt32() } == (0..<64).map { _ in b.nextUInt32() })
    }

    @Test func entropyInitGivesDistinctSeeds() {
        // Two 64-bit entropy draws collide with probability 2^-64.
        let a = Random()
        let b = Random()
        #expect(a.seed != b.seed)
        // The instance is usable and reproducible from its reported seed.
        let replay = Random(seed: a.seed)
        #expect((0..<16).map { _ in a.nextUInt32() } == (0..<16).map { _ in replay.nextUInt32() })
    }

    @Test func reseedDropsCachedNormal() {
        let r = Random(seed: 9)
        let first = r.normal()
        _ = r.normal()                 // second value of the pair
        r.reseed(9)
        _ = r.normal()                 // computes a fresh pair
        r.reseed(9)
        #expect(r.normal() == first)   // not the stale spare
    }

    @Test(arguments: [0, -1, Int.min, 1])
    func uniformIntWithoutDraw(_ n: Int) {
        // n <= 0 and n == 1 return 0 without consuming a draw.
        let r = Random(seed: 3)
        let ref = Random(seed: 3)
        #expect(r.uniformInt(n) == 0)
        #expect(r.nextUInt32() == ref.nextUInt32())
    }

    @Test func uniformIntFullRangeStaysInRange() {
        let r = Random(seed: 11)
        let n = Int(UInt32.max)
        for _ in 0..<1000 {
            let v = r.uniformInt(n)
            #expect(v >= 0 && v < n)
        }
    }

    @Test func uniformIntRejectsRangeWiderThan32Bits() async {
        await #expect(processExitsWith: .failure) {
            _ = Random(seed: 1).uniformInt(Int(UInt32.max) + 1)
        }
    }
}

// MARK: - delphiRound

@Suite struct DelphiRoundTests {
    @Test func doubleIsBankers() {
        #expect(delphiRound(24.5) == 24)
        #expect(delphiRound(25.5) == 26)
        #expect(delphiRound(-0.5) == 0)
        #expect(delphiRound(1102.5) == 1102)
        #expect(delphiRound(1.4999) == 1)
    }

    @Test(arguments: [
        (Float(0.5), 0), (1.5, 2), (2.5, 2), (3.5, 4), (-0.5, 0), (-1.5, -2), (-2.5, -2),
        (24.5, 24), (0.49999997, 0), (1.0000001, 1), (-0.0, 0), (8_388_607.5, 8_388_608),
        (16_777_216, 16_777_216),
    ])
    func floatIsBankers(_ x: Float, _ expected: Int) {
        #expect(delphiRound(x) == expected)
    }

    @Test func floatMatchesDoubleOfSameValue() {
        var x: Float = -1000
        while x <= 1000 {
            #expect(delphiRound(x) == delphiRound(Double(x)))
            x += 0.25
        }
    }

    @Test func extremesThatFitInInt() {
        #expect(delphiRound(-9_223_372_036_854_775_808.0) == Int.min)
        #expect(delphiRound(9_223_372_036_854_774_784.0) == 9_223_372_036_854_774_784)
    }

    @Test func nanTraps() async {
        await #expect(processExitsWith: .failure) { _ = delphiRound(Double.nan) }
    }

    @Test func infinityTraps() async {
        await #expect(processExitsWith: .failure) { _ = delphiRound(Float.infinity) }
    }

    @Test func outOfIntRangeTraps() async {
        await #expect(processExitsWith: .failure) { _ = delphiRound(9_223_372_036_854_775_808.0) }
    }
}

// MARK: - sinCos

@Suite struct SinCosTests {
    private static let floatAngles: [Float] = [
        0, -0.0, 1.0e-7, 0.5, 1, 2, 3.1415927, -3.1415927, 6.2831855, 100, -1234.5, 1.0e6,
        Float(MathK.twoPi) / 18, Float(MathK.twoPi) * 0.737,
    ]

    @Test(arguments: floatAngles)
    func floatIsTheSincosStretCall(_ x: Float) {
        let sc = sinCos(x)
        let ref = __sincosf_stret(x)
        #expect(sc.sin.bitPattern == ref.__sinval.bitPattern)
        #expect(sc.cos.bitPattern == ref.__cosval.bitPattern)
        // Within one ulp of the separate libm calls.
        #expect(abs(sc.sin - sin(x)) <= sin(x).ulp)
        #expect(abs(sc.cos - cos(x)) <= cos(x).ulp)
    }

    @Test(arguments: floatAngles.map(Double.init) + [MathK.twoPi / 18, MathK.twoPi / 24.5, 1.0e10])
    func doubleIsTheSincosStretCall(_ x: Double) {
        let sc = sinCos(x)
        let ref = __sincos_stret(x)
        #expect(sc.sin.bitPattern == ref.__sinval.bitPattern)
        #expect(sc.cos.bitPattern == ref.__cosval.bitPattern)
        #expect(abs(sc.sin - sin(x)) <= sin(x).ulp)
        #expect(abs(sc.cos - cos(x)) <= cos(x).ulp)
    }
}

// MARK: - AudioK

@Suite struct AudioKTests {
    @Test(arguments: zip(1...5, [128, 256, 512, 1024, 2048]))
    func bufferSamplesIs64ShlExp(_ exp: Int, _ samples: Int) {
        #expect(AudioK.bufferSamples(forExp: exp) == samples)
    }

    @Test func defaultBufferIs512() {
        #expect(AudioK.defaultBufferSamples == 512)
        #expect(AudioK.bufferSamples(forExp: AudioK.bufferExpDefault) == AudioK.defaultBufferSamples)
    }

    @Test func blocksToSeconds() {
        #expect(AudioK.blocksToSeconds(1) == 512.0 / 11025.0)
        #expect(AudioK.blocksToSeconds(10, bufSize: 2048) == 10.0 * 2048.0 / 11025.0)
        #expect(AudioK.blocksToSeconds(0) == 0)
    }

    @Test(arguments: [
        // (seconds, bufSize, blocks); 11025 / 2205 = 5 exactly, so the
        // 2205 rows land on exact halves and round to even.
        (1.0, 512, 22), (0.0, 512, 0), (60.0, 512, 1292), (0.5, 2205, 2), (1.5, 2205, 8),
        (2.5, 2205, 12), (0.3, 2205, 2), (-0.5, 2205, -2), (1.0, 128, 86),
    ])
    func secondsToBlocksRoundsHalfToEven(_ s: Double, _ bufSize: Int, _ blocks: Int) {
        #expect(AudioK.secondsToBlocks(s, bufSize: bufSize) == blocks)
    }

    @Test func secondsToBlocksRejectsZeroBuffer() async {
        await #expect(processExitsWith: .failure) { _ = AudioK.secondsToBlocks(1, bufSize: 0) }
    }
}
