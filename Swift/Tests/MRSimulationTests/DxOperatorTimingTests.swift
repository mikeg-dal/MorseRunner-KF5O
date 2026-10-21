// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// DxOperator's random quantities (C++ DxOperator.cpp getNumber,
// getSendDelayBlocks, getReplyTimeoutBlocks). Each expected value is the
// C++ expression evaluated on a second Random with the same seed, so the
// tests pin both the arithmetic and the number of draws.

import MRCore
@testable import MRSimulation
import Testing

/// C++ DxOperator.cpp secondsToBlocks(float): fixed 512-sample buffer.
private func cppSecondsToBlocks(_ seconds: Float) -> Int {
    delphiRound(Double(seconds) * 11025.0 / 512.0)
}

private func makeOp(seed: UInt64, mode: RunMode = .pileUp, wpm: Int = 30,
                    skills: Int = 1) -> (FakeEngine, DxOperator, Random) {
    let eng = FakeEngine(seed: seed)
    eng.runMode = mode
    eng.targetWpm = wpm
    let op = DxOperator(engine: eng)  // NeedPrevEnd: no draws
    op.call = "W1AW"
    op.skills = skills
    return (eng, op, Random(seed: seed))
}

@Suite struct DxOperatorTimingTests {
    @Test(arguments: [1, 2, 3])
    func randomNumberGrowsWithMinuteAndSkill(skills: Int) {
        let (eng, op, ref) = makeOp(seed: 17, skills: skills)
        eng.currentMinute = 12.5
        for _ in 0..<20 {
            // C++: 1 + delphiRound(u * minute * skills) in double.
            let u = Double(ref.uniform01())
            let expected = 1 + delphiRound(u * 12.5 * Double(skills))
            #expect(op.randomNumber() == expected)
        }
        withExtendedLifetime(eng) {}
    }

    @Test func randomNumberAtMinuteZeroIsOne() {
        let (eng, op, _) = makeOp(seed: 4)
        eng.currentMinute = 0
        for _ in 0..<10 {
            #expect(op.randomNumber() == 1)
        }
    }

    @Test func sendDelayIsNeverInNeedPrevEndWithoutADraw() {
        let (eng, op, ref) = makeOp(seed: 8)
        #expect(op.state == .needPrevEnd)
        #expect(op.sendDelayBlocks() == kNeverTimeout)
        // No draw consumed: both generators are still in step.
        #expect(eng.random.uniform01() == ref.uniform01())
    }

    @Test func sendDelayOutsideHstIsOneHundredToSixHundredMs() {
        let (eng, op, ref) = makeOp(seed: 9)
        op.setState(.needEnd)  // no draws outside NeedQso
        for _ in 0..<50 {
            let u = ref.uniform01()
            let s: Float = 0.1 + 0.5 * u
            let got = op.sendDelayBlocks()
            #expect(got == cppSecondsToBlocks(s))
            #expect((2...13).contains(got))  // round(0.1·21.53) ... round(0.6·21.53)
        }
        withExtendedLifetime(eng) {}
    }

    @Test(arguments: [10, 25, 60])
    func sendDelayInHstScalesWithSpeed(wpm: Int) {
        let (eng, op, ref) = makeOp(seed: 10, mode: .hst, wpm: wpm)
        op.setState(.needNr)
        for _ in 0..<50 {
            let u = ref.uniform01()
            let s: Float = 0.05 + 0.5 * u * 10.0 / Float(wpm)
            #expect(op.sendDelayBlocks() == cppSecondsToBlocks(s))
        }
        withExtendedLifetime(eng) {}
    }

    /// C++: blocks = secondsToBlocks(base); max(1, round(gaussLim(blocks, blocks/2))).
    private func expectedReplyTimeout(_ base: Float, _ ref: Random) -> Int {
        let blocks = cppSecondsToBlocks(base)
        return max(1, delphiRound(ref.gaussLim(Float(blocks), Float(blocks) / 2.0)))
    }

    @Test(arguments: zip([0, 1, 2, 3, 5, 6], [129, 108, 86, 65, 22, 0]))
    func replyTimeoutOutsideHstUsesSixMinusSkills(skills: Int, baseBlocks: Int) {
        // Skills 1...3 are what DxStation draws; 0, 5 and 6 check the
        // arithmetic carries on unguarded, as in the C++ (6 → 0 s → the
        // max(1, …) floor). Skills above 6 give a negative gaussLim limit,
        // undefined behaviour for the C++ std::clamp, so they are not
        // pinned here.
        #expect(cppSecondsToBlocks(Float(6 - skills)) == baseBlocks)
        let (eng, op, ref) = makeOp(seed: 11, skills: skills)
        for _ in 0..<30 {
            let expected = expectedReplyTimeout(Float(6 - skills), ref)
            let got = op.replyTimeoutBlocks()
            #expect(got == expected)
            #expect(got >= 1)
            #expect(got <= max(1, baseBlocks + (baseBlocks + 1) / 2))
        }
        withExtendedLifetime(eng) {}
    }

    @Test func replyTimeoutInHstIsSixtyOverWpm() {
        let (eng, op, ref) = makeOp(seed: 12, mode: .hst, wpm: 30, skills: 3)
        #expect(cppSecondsToBlocks(60.0 / 30.0) == 43)
        for _ in 0..<30 {
            #expect(op.replyTimeoutBlocks() == expectedReplyTimeout(Float(60.0) / Float(30.0), ref))
        }
        withExtendedLifetime(eng) {}
    }

    @Test func randomWpmOutsideHstMatchesCppFormula() {
        let (eng, op, ref) = makeOp(seed: 13, wpm: 35)
        for _ in 0..<30 {
            let expected = delphiRound(35.0 * 0.5 * (1.0 + Double(ref.uniform01())))
            #expect(op.randomWpm() == expected)
        }
        withExtendedLifetime(eng) {}
    }

    @Test func setStateNeedQsoDrawsPatienceAndRepeat() {
        let (eng, op, ref) = makeOp(seed: 14)
        op.setState(.needQso)
        let patience = delphiRound(ref.rayleigh(4.0))
        let repeatCount = ref.uniform01() < 0.1 ? 2 : 1
        #expect(op.patience == patience)
        #expect(op.repeatCount == repeatCount)
        // Other states: fullPatience (5), repeat 1, no draws.
        op.setState(.needEnd)
        #expect(op.patience == 5)
        #expect(op.repeatCount == 1)
        #expect(eng.random.uniform01() == ref.uniform01())
    }

    @Test func singleAndHstNeverRepeat() {
        for mode in [RunMode.single, .hst] {
            let (eng, op, _) = makeOp(seed: 15, mode: mode)
            for _ in 0..<200 {
                op.setState(.needQso)
                #expect(op.repeatCount == 1)
            }
            withExtendedLifetime(eng) {}
        }
    }

    @Test func hstWpmZeroTrapsInsteadOfDividingByZero() async {
        await #expect(processExitsWith: .failure) {
            let eng = FakeEngine(seed: 1)
            eng.runMode = .hst
            eng.targetWpm = 0
            let op = DxOperator(engine: eng)
            op.setState(.needNr)
            _ = op.replyTimeoutBlocks()
        }
        await #expect(processExitsWith: .failure) {
            let eng = FakeEngine(seed: 1)
            eng.runMode = .hst
            eng.targetWpm = 0
            let op = DxOperator(engine: eng)
            op.setState(.needNr)
            _ = op.sendDelayBlocks()
        }
    }

    @Test func wpmZeroOutsideHstDoesNotDivide() {
        let (eng, op, _) = makeOp(seed: 16, wpm: 0)
        op.setState(.needNr)
        #expect(op.randomWpm() == 0)
        #expect(op.sendDelayBlocks() >= 2)
        #expect(op.replyTimeoutBlocks() >= 1)
        withExtendedLifetime(eng) {}
    }
}
