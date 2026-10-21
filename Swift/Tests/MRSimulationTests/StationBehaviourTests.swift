// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Station, MyStation, DxStation and StationCollection paths not covered
// by the C++-ported tests, plus MessageSet and the Engine defaults.
// Stations hold their engine unowned, so every test keeps its
// FakeEngine alive until the end (withExtendedLifetime).

import MRCore
@testable import MRSimulation
import Testing

/// Keys `station` out completely (getBlock until the envelope is gone).
private func drainEnvelope(_ station: Station, maxBlocks: Int = 2000) {
    var buf = [Float](repeating: 0, count: 512)
    var n = 0
    while !station.envelopeExhausted && n < maxBlocks {
        station.getBlock(&buf)
        n += 1
    }
}

@Suite struct StationBehaviourTests {
    @Test func setRstIsUsedForTheNumber() {
        let eng = FakeEngine(seed: 1)
        let refEng = FakeEngine(seed: 1)
        let dx = DxStation(engine: eng, call: "W1AW")
        let refDx = DxStation(engine: refEng, call: "W1AW")  // same draws
        withExtendedLifetime((eng, refEng, refDx)) {
            dx.setRst(579)
            dx.setNr(7)
            dx.nrWithError = false
            #expect(dx.rst == 579)
            dx.sendText("<#>")
            let expected = nrAsText(NrFormatOptions(rst: 579, nr: 7), refEng.random)
            #expect(dx.accumulatedText == expected)
            #expect(expected.hasPrefix("57"))
        }
    }

    @Test func envelopeExhaustedTracksTheCursor() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            #expect(me.envelopeExhausted)  // nothing queued
            me.sendMsg(.cq)
            #expect(!me.envelopeExhausted)
            var buf = [Float](repeating: 0, count: 512)
            me.getBlock(&buf)
            #expect(!me.envelopeExhausted)
            drainEnvelope(me)
            #expect(me.envelopeExhausted)
        }
    }

    // Pascal TStation.SendText replaces the first <#> (carrying the LID
    // error) and then all the rest with one fresh, error-free value.
    @Test func rNr2LidErrorOnlyInTheFirstNumber() {
        for seed: UInt64 in 1...30 {
            let eng = FakeEngine(seed: seed)
            let refEng = FakeEngine(seed: seed)
            let dx = DxStation(engine: eng, call: "W1AW")
            let refDx = DxStation(engine: refEng, call: "W1AW")
            withExtendedLifetime((eng, refEng, refDx)) {
                dx.setNr(57)  // last digit 7 is in 2..7, so the error always applies
                dx.nrWithError = true
                dx.sendText(Message.rNr2.template)
                #expect(!dx.nrWithError, "the error flag is consumed")

                let first = nrAsText(NrFormatOptions(rst: dx.rst, nr: 57, lidError: true), refEng.random)
                let rest = nrAsText(NrFormatOptions(rst: dx.rst, nr: 57), refEng.random)
                #expect(dx.accumulatedText == "R \(first) \(rest)")
                #expect(first.contains("EEEEE"))
                #expect(!rest.contains("EEEEE"))
            }
        }
    }

    @Test func multipleNumberSlotsWithoutErrorShareOneValue() {
        let eng = FakeEngine(seed: 3)
        let refEng = FakeEngine(seed: 3)
        let dx = DxStation(engine: eng, call: "W1AW")
        let refDx = DxStation(engine: refEng, call: "W1AW")
        withExtendedLifetime((eng, refEng, refDx)) {
            dx.nrWithError = false
            dx.sendText("<#> <#> <#>")
            let first = nrAsText(NrFormatOptions(rst: dx.rst, nr: dx.nr), refEng.random)
            let rest = nrAsText(NrFormatOptions(rst: dx.rst, nr: dx.nr), refEng.random)
            #expect(dx.accumulatedText == "\(first) \(rest) \(rest)")
        }
    }

    @Test func neverTimeoutIsNotDecremented() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            #expect(dx.state == .copying)
            dx.setTimeout(kNeverTimeout)
            for _ in 0..<5 { dx.tick() }
            #expect(dx.timeout == kNeverTimeout)
            #expect(kNeverTimeout == Int(Int32.max))
        }
    }

    @Test func timeoutStopsAtMinusOne() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            dx.setTimeout(0)
            dx.tick()
            #expect(dx.timeout == -1)
            dx.tick()
            #expect(dx.timeout == -1)
        }
    }

    @Test func getBlockInoutCopiesAndLeavesTheTailAlone() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.sendMsg(.cq)
            let total = me.envelope.count
            #expect(total > 0)
            let expected = me.envelope
            var copied: [Float] = []
            var buf = [Float](repeating: 0, count: 4096)
            while copied.count < total {
                buf = [Float](repeating: -7, count: 4096)
                let got = me.getBlock(&buf)
                #expect(got > 0)
                copied += buf[0..<got]
                if got < buf.count {
                    #expect(buf[got...].allSatisfy { $0 == -7 })
                }
            }
            #expect(copied == expected)
            #expect(me.getBlock(&buf) == 0)
        }
    }

    @Test func getBlockReturnsZeroWhenNotSending() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            var buf = [Float](repeating: 3, count: 16)
            #expect(me.getBlock(&buf) == 0)
            #expect(buf.allSatisfy { $0 == 3 })
        }
    }
}

@Suite struct MyStationTests {
    @Test func updateWithEmptyCallIsRejected() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendMsg(.hisCall)
            #expect(!me.updateCallInMessage(""))
            #expect(me.hisCall == "W1AW")
        }
    }

    @Test func updateWithNothingQueuedIsRejected() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            #expect(!me.updateCallInMessage("K2ABC"))
            me.sendMsg(.cq)  // no <his> anywhere
            #expect(!me.updateCallInMessage("K2ABC"))
            #expect(me.hisCall == "")
        }
    }

    @Test func updateBeforeKeyingSwapsTheEnvelope() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendMsg(.hisCall)
            let before = me.envelope
            #expect(me.updateCallInMessage("K2ABCD"))
            #expect(me.hisCall == "K2ABCD")
            #expect(me.envelope != before)
        }
    }

    @Test func updateMidCallNeedsTheKeyedPrefixToMatch() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendMsg(.hisCall)
            var buf = [Float](repeating: 0, count: 512)
            me.getBlock(&buf)
            me.getBlock(&buf)  // ~93 ms of the leading "W" keyed
            #expect(!me.updateCallInMessage("K1AW"))  // already keyed W
            #expect(me.hisCall == "W1AW")
            #expect(me.updateCallInMessage("W1AX"))
            #expect(me.hisCall == "W1AX")
        }
    }

    @Test func updateFallsThroughToAQueuedSecondCall() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendMsg(.nr)       // keying "<#>" now
            me.sendMsg(.hisCall)  // <his> queued behind it
            #expect(me.pieceCount == 2)
            #expect(me.updateCallInMessage("K2ABC"))
            #expect(me.hisCall == "K2ABC")
        }
    }

    @Test func sendTextSplitsEveryHisToken() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendText("<his> TU <his><his> 5NN")
            // "@", " TU ", "@", "@", " 5NN"
            #expect(me.pieceCount == 5)
            #expect(me.state == .sending)
            #expect(me.accumulatedText == "W1AW")
        }
    }

    @Test func setMsgOverwritesTheMessageSet() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.sendMsg(.tu)
            #expect(me.msg == MessageSet([.tu]))
            me.setMsg(MessageSet([.cq]))
            #expect(me.msg == MessageSet([.cq]))
        }
    }

    @Test func pieceFinishedFiresOncePerPiece() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            var fired = 0
            me.pieceFinished = { fired += 1 }
            me.setHisCall("W1AW")
            me.sendMsg(.hisCall)
            me.sendMsg(.nr)
            #expect(me.pieceCount == 2)
            var buf = [Float](repeating: 0, count: 512)
            var n = 0
            while me.pieceCount > 0 && n < 2000 {
                me.getBlock(&buf)
                n += 1
            }
            #expect(fired == 2)
            #expect(me.pieceCount == 0)
        }
    }

    @Test func abortClearsPiecesAndMarksGarbage() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.sendMsg(.hisCall)
            me.sendMsg(.nr)
            me.abortSend()
            #expect(me.pieceCount == 0)
            #expect(me.msg == MessageSet([.garbage]))
            #expect(me.envelopeExhausted)
        }
    }
}

@Suite struct DxStationTests {
    @Test func shouldRemoveOnFailureOrRelease() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            #expect(!dx.shouldRemove)
            dx.dxOperator.setState(.done)
            #expect(dx.isFinished)
            #expect(!dx.shouldRemove)  // Done waits for its QSO to be logged
            dx.release()
            #expect(dx.shouldRemove)

            let dx2 = DxStation(engine: eng, call: "K2ABC")
            dx2.dxOperator.setState(.failed)
            #expect(dx2.shouldRemove)
        }
    }

    // Timeout while listening: the operator hears "nothing" (a set with
    // only .none); if that exhausts its patience it fails and sends nothing.
    @Test func timeoutThatFailsTheOperatorSendsNothing() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            dx.dxOperator.setState(.needNr)  // patience 5
            var nothing = MessageSet()
            nothing.insert(.none)
            for _ in 0..<4 { dx.dxOperator.onMessageReceived(nothing) }
            #expect(dx.dxOperator.patience == 1)
            dx.state = .listening
            dx.setTimeout(1)
            dx.tick()  // → Timeout event
            #expect(dx.dxOperator.state == .failed)
            #expect(dx.state == .listening)
            #expect(dx.envelopeExhausted)
            #expect(dx.shouldRemove)
        }
    }

    @Test func timeoutWithPatienceLeftReplies() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            dx.dxOperator.setState(.needEnd)  // patience 5
            dx.state = .listening
            dx.setTimeout(1)
            dx.tick()
            #expect(dx.dxOperator.state == .needEnd)
            #expect(dx.state == .sending)
            #expect(dx.msg.contains(.rNr) || dx.msg.contains(.rNr2))
        }
    }

    @Test func doneStationIgnoresEvents() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        withExtendedLifetime(eng) {
            dx.dxOperator.setState(.done)
            let before = (dx.state, dx.timeout)
            dx.processEvent(.meFinished)
            dx.processEvent(.meStarted)
            dx.processEvent(.msgSent)
            #expect(dx.state == before.0)
            #expect(dx.timeout == before.1)
        }
    }
}

@Suite struct StationCollectionExtraTests {
    @Test func dxCountExcludesDoneButNotYetRemoved() {
        let eng = FakeEngine(seed: 6)
        let sc = StationCollection()
        withExtendedLifetime(eng) {
            let a = sc.addCaller(eng, "W1AW")
            sc.addCaller(eng, "K2ABC")
            a.dxOperator.setState(.done)
            sc.sweep()
            #expect(sc.count == 2)
            #expect(sc.dxCount == 1)
        }
    }

    @Test func sweepKeepsSurvivorOrder() {
        let eng = FakeEngine(seed: 7)
        let sc = StationCollection()
        withExtendedLifetime(eng) {
            let calls = ["A1A", "B2B", "C3C", "D4D", "E5E"]
            let dxs = calls.map { sc.addCaller(eng, $0) }
            dxs[1].dxOperator.setState(.failed)
            dxs[3].release()
            sc.sweep()
            #expect(sc.map(\.myCall) == ["A1A", "C3C", "E5E"])
        }
    }
}

@Suite struct MessageSetTests {
    @Test func rawValueRoundTrips() {
        let s = MessageSet(rawValue: (1 << 1) | (1 << 3))
        #expect(s.contains(.cq))
        #expect(s.contains(.tu))
        #expect(s.count == 2)
        #expect(s == MessageSet([.cq, .tu]))
        #expect(MessageSet(rawValue: 0).isEmpty)
        #expect(MessageSet().isEmpty)
    }

    @Test func unionOperators() {
        let a = MessageSet([.cq])
        let b = MessageSet([.nr, .tu])
        #expect((a | b).rawValue == a.rawValue | b.rawValue)
        var c = a
        c |= b
        #expect(c == a | b)
        #expect(c == a.union(b))  // OptionSet algebra agrees
        #expect(c.isSuperset(of: a))
    }

    @Test func insertNoneSetsBitZeroButIsNeverContained() {
        var s = MessageSet()
        s.insert(.none)
        #expect(!s.isEmpty)
        #expect(s.count == 1)
        #expect(s.rawValue == 1)
        #expect(!s.contains(.none))
        #expect(MessageSet.of(.none).isEmpty)
        #expect(MessageSet([.none]).rawValue == 1)
    }

    @Test func resetEmpties() {
        var s = MessageSet([.cq, .agn])
        s.reset()
        #expect(s.isEmpty)
        #expect(s == [])
    }

    @Test func everyMessageHasItsOwnBit() {
        var all = MessageSet()
        for m in Message.allCases where m != .none {
            #expect(!all.contains(m))
            all.insert(m)
            #expect(all.contains(m))
        }
        #expect(all.count == Message.allCases.count - 1)
    }
}

/// An Engine that relies on every protocol default.
private final class MinimalEngine: Engine {
    let random = Random(seed: 1)
    var currentBlockIndex: Int { 0 }
    var currentMinute: Float { 0 }
    var myCallsign: String { "VE3NEA" }
    var heardCallsign: String { "" }
    var myLastMessage: MessageSet { MessageSet() }
    var runMode: RunMode { .pileUp }
    var lidsEnabled: Bool { false }
    var flutterEnabled: Bool { false }
    var qsbEnabled: Bool { false }
    var targetWpm: Int { 30 }
    var activity: Int { 3 }
    var bufferSize: Int { 512 }
}

@Suite struct EngineDefaultsTests {
    @Test func defaultsAreQuiet() {
        let eng = MinimalEngine()
        #expect(!eng.playerSending)
        #expect(!eng.callsFromKeyer)
        eng.onPlayerStartedSending()
        eng.onPlayerFinishedSending()
        // A player station on it keys normally with the no-op hooks.
        let me = MyStation(engine: eng)
        withExtendedLifetime(eng) {
            me.setHisCall("W1AW")
            me.sendMsg(.hisCall)
            #expect(me.accumulatedText == "W1AW")
            me.abortSend()
            #expect(me.state == .listening)
        }
    }
}
