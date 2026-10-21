// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of tests/simulation/test_dx_operator_fsm.cpp.

import MRCore
@testable import MRSimulation
import Testing

private func setOf(_ ms: [Message]) -> MessageSet { MessageSet(ms) }

@Suite struct DxOperatorFsmTests {
    @Test func initialStateIsNeedPrevEnd() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        #expect(op.state == .needPrevEnd)
    }

    @Test func cqHeardFromPrevEndTransitionsToNeedQso() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needPrevEnd)
        op.onMessageReceived(setOf([.cq]))
        #expect(op.state == .needQso)
    }

    @Test func replyFromNeedQsoIsMyCall() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needQso)
        #expect(op.reply() == .myCall)
    }

    @Test func correctCallTransitionsToNeedNr() {
        let eng = FakeEngine()
        eng.heardCallsign = "W1AW"
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needQso)
        op.onMessageReceived(setOf([.hisCall]))
        #expect(op.state == .needNr)
    }

    @Test func almostCallFromNeedQsoTransitionsToNeedCallNr() {
        let eng = FakeEngine()
        eng.heardCallsign = "W1AX"  // single-char typo on a 4-char call → Almost
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needQso)
        op.onMessageReceived(setOf([.hisCall]))
        #expect(op.state == .needCallNr)
    }

    @Test func wrongCallFromNeedQsoReturnsToNeedPrevEnd() {
        let eng = FakeEngine()
        eng.heardCallsign = "JA1XYZ"
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needQso)
        op.onMessageReceived(setOf([.hisCall]))
        #expect(op.state == .needPrevEnd)
    }

    @Test func nrThenTuCompletesQso() {
        let eng = FakeEngine()
        eng.heardCallsign = "W1AW"
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needNr)
        eng.random.reseed(1)
        op.onMessageReceived(setOf([.hisCall, .nr]))
        // NeedEnd, or NeedNr on the 10% retry — either is port-faithful.
        #expect(op.state == .needEnd || op.state == .needNr)
        if op.state == .needEnd {
            op.onMessageReceived(setOf([.tu]))
            #expect(op.state == .done)
        }
    }

    @Test func nilWhileWaitingForReplyIsFailed() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needNr)
        op.onMessageReceived(setOf([.nilMsg]))
        #expect(op.state == .failed)
    }

    @Test func b4DuringQsoIsFailed() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needNr)
        op.onMessageReceived(setOf([.b4]))
        #expect(op.state == .failed)
    }

    @Test func patienceExhaustionTriggersFailure() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needEnd)  // fullPatience = 5
        // Bare Nr has no NeedEnd transition, but the per-call patience
        // decrement still fires.
        for _ in 0..<10 where op.state != .failed {
            op.onMessageReceived(setOf([.nr]))
        }
        #expect(op.state == .failed)
    }

    @Test func getWpmInHstMatchesEngineTarget() {
        let eng = FakeEngine()
        eng.runMode = .hst
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        #expect(op.randomWpm() == eng.targetWpm)
    }

    @Test func getWpmInPileUpIsHalfToFull() {
        let eng = FakeEngine()
        eng.runMode = .pileUp
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        for _ in 0..<50 {
            let w = op.randomWpm()
            #expect(w >= eng.targetWpm / 2)
            #expect(w <= eng.targetWpm)
        }
    }

    @Test func getReplyAfterFailureIsNone() {
        let eng = FakeEngine()
        let op = DxOperator(engine: eng)
        op.call = "W1AW"
        op.setState(.needNr)
        op.onMessageReceived(setOf([.nilMsg]))
        #expect(op.reply() == Message.none)
    }
}
