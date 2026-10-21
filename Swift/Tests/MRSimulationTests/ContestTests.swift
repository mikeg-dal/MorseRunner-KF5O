// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of tests/simulation/test_contest.cpp.

import Foundation
import MRCore
@testable import MRSimulation
import Testing

private let kBuf = AudioK.defaultBufferSamples

private func makeContest(seed: UInt64) -> Contest {
    Contest(calls: HardcodedCallsignSource(), bufferSize: kBuf, random: Random(seed: seed))
}

/// True if any DX caller is transmitting within `blocks` blocks.
private func aDxCallsWithin(_ contest: Contest, _ blocks: Int) -> Bool {
    var buf = [Float](repeating: 0, count: kBuf)
    for _ in 0..<blocks {
        contest.renderNextBlock(&buf)
        for s in contest.stations where s is DxStation && s.state == .sending {
            return true
        }
    }
    return false
}

@Suite struct ContestTests {
    @Test func renderInStopModeIsSilence() {
        let contest = makeContest(seed: 1)
        var buf = [Float](repeating: 99, count: kBuf)
        #expect(contest.renderNextBlock(&buf) == kBuf)
        #expect(buf.allSatisfy { $0 == 0 })
    }

    @Test func firstBlocksAreSilenceForStartupSkip() {
        let contest = makeContest(seed: 2)
        contest.setRunMode(.pileUp)
        var buf = [Float](repeating: 99, count: kBuf)
        // Pascal: skip first 5 (startupSkipBlocks = 6, condition is < 6).
        for b in 0..<(AudioK.startupSkipBlocks - 1) {
            buf = [Float](repeating: 99, count: kBuf)
            contest.renderNextBlock(&buf)
            #expect(buf.allSatisfy { $0 == 0 }, "block \(b)")
        }
    }

    @Test func producesBoundedAudioAfterStartupSkip() {
        let contest = makeContest(seed: 42)
        contest.setRunMode(.pileUp)
        var buf = [Float](repeating: 0, count: kBuf)
        var anyNonZero = false
        var allFinite = true
        var allBounded = true
        for _ in 0..<50 {
            contest.renderNextBlock(&buf)
            for s in buf {
                if !s.isFinite { allFinite = false }
                if abs(s) > 1.5 { allBounded = false }  // small AGC headroom slop
                if s != 0 { anyNonZero = true }
            }
        }
        #expect(allFinite)
        #expect(allBounded)
        #expect(anyNonZero, "Expected audible content within 50 blocks")
    }

    @Test func endOfSessionFiresAtDurationLimit() {
        let contest = makeContest(seed: 7)
        var s = ContestSettings()
        s.durationMinutes = 0  // ends after the first audible block
        contest.setSettings(s)
        contest.setRunMode(.pileUp)
        var fired = false
        var mode: RunMode?
        var byUserSeen: Bool?
        contest.onEndOfSession = { m, byUser in
            fired = true
            mode = m
            byUserSeen = byUser
        }
        var buf = [Float](repeating: 0, count: kBuf)
        for _ in 0..<12 where !fired {
            contest.renderNextBlock(&buf)
        }
        #expect(fired)
        #expect(mode == .pileUp)
        #expect(byUserSeen == false)
        // After end-of-session the mode returns to Stop.
        #expect(contest.runMode == .stop)
    }

    @Test func requestStopForcesEndOfSession() {
        let contest = makeContest(seed: 11)
        contest.setRunMode(.pileUp)
        var fired = false
        var byUserSeen: Bool?
        contest.onEndOfSession = { _, byUser in
            fired = true
            byUserSeen = byUser  // Pascal FStopPressed
        }
        contest.requestStop()
        var buf = [Float](repeating: 0, count: kBuf)
        for _ in 0..<12 where !fired {
            contest.renderNextBlock(&buf)
        }
        #expect(fired)
        #expect(byUserSeen == true)
    }

    @Test func pileUpStartsSilentUntilPlayerCq() {
        // Pascal parity: starting Pile-Up keys nothing, so no callers
        // appear until the player sends CQ (F1).
        let contest = makeContest(seed: 1234)
        contest.setRunMode(.pileUp)
        #expect(contest.player.state != .sending)
        var buf = [Float](repeating: 0, count: kBuf)
        for _ in 0..<500 {
            contest.renderNextBlock(&buf)
        }
        #expect(contest.stations.dxCount == 0)
    }

    @Test func pileUpPlayerCqDrawsCallers() {
        let contest = makeContest(seed: 1234)
        contest.setRunMode(.pileUp)
        contest.playerSendMessage(.cq)
        var buf = [Float](repeating: 0, count: kBuf)
        var sawCaller = false
        for _ in 0..<500 where !sawCaller {
            contest.renderNextBlock(&buf)
            sawCaller = contest.stations.dxCount > 0
        }
        #expect(sawCaller)
    }

    @Test func keysPressedWhileStoppedAreDroppedOnRun() {
        let contest = makeContest(seed: 5)
        contest.setRunMode(.stop)
        contest.playerSendMessage(.cq)
        contest.playerSendMessage(.cq)
        contest.setRunMode(.pileUp)
        #expect(contest.player.state != .sending)
    }

    // Pascal Contest.GetAudio hands each auto-spawned Single Calls / HST
    // caller an evMeFinished (with Me.Msg = [msgCQ]) so it calls on its own.
    @Test func singleCallsCallerCallsWithoutPlayerInput() {
        let contest = makeContest(seed: 7)
        contest.setRunMode(.single)
        #expect(aDxCallsWithin(contest, 220))
    }

    @Test func hstCallersCallWithoutPlayerInput() {
        let contest = makeContest(seed: 8)
        contest.setRunMode(.hst)
        #expect(aDxCallsWithin(contest, 220))
    }

    // Pascal Log.SaveQso ends with Inc(Tst.Me.NR); Run resets it to 1.
    @Test func serialNumberAdvancesPerLoggedQso() {
        let contest = makeContest(seed: 21)
        contest.setRunMode(.pileUp)
        #expect(contest.player.nr == 1)
        contest.qsoLogged("W1AW")
        contest.qsoLogged("K2ABC")
        #expect(contest.player.nr == 3)
        contest.setRunMode(.stop)
        contest.setRunMode(.pileUp)
        #expect(contest.player.nr == 1)
    }

    // Pascal TMainForm.SendMsg: Me.HisCall follows the Call box only when
    // HisCall is sent, and an empty box keeps the previous call.
    @Test func hisCallIsWhatWasSent() {
        let contest = makeContest(seed: 22)
        contest.setRunMode(.pileUp)
        contest.playerSendMessage(.hisCall, callField: "w1aw")
        #expect(contest.heardCallsign == "W1AW")
        contest.playerSendMessage(.hisCall, callField: "")
        #expect(contest.heardCallsign == "W1AW")
        // While the call is still queued, an edit replaces it.
        #expect(contest.playerEditedCall("K2ABC"))
        #expect(contest.heardCallsign == "K2ABC")
        // Once nothing is being sent, typing does not change what the DX
        // compares against, and the GUI is told to clear CallSent.
        _ = contest.playerAbortSend()
        #expect(!contest.playerEditedCall("N3XYZ"))
        #expect(contest.heardCallsign == "K2ABC")
    }

    // Pascal TContest.OnMeFinishedSending: TU + MyCall only counts as a CQ
    // once something is in the log (QsoList <> nil).
    @Test func tuMyCallDrawsCallersOnlyAfterFirstQso() {
        var s = ContestSettings()
        s.activity = 9  // Poisson(4.5): zero callers is very unlikely
        let contest = makeContest(seed: 23)
        contest.setSettings(s)
        contest.setRunMode(.pileUp)

        func sendTuMyCallAndFinish() {
            contest.playerSendMessage(.tu)
            contest.playerSendMessage(.myCall)
            var buf = [Float](repeating: 0, count: kBuf)
            var b = 0
            while b < 200 && contest.playerSending {
                contest.renderNextBlock(&buf)
                b += 1
            }
            // One more block so the player's MsgSent fires.
            contest.renderNextBlock(&buf)
        }

        sendTuMyCallAndFinish()
        #expect(contest.stations.dxCount == 0)

        contest.qsoLogged("W1AW")
        sendTuMyCallAndFinish()
        #expect(contest.stations.dxCount > 0)
    }

    @Test func renderRejectsShortBuffer() {
        let contest = makeContest(seed: 1)
        var buf = [Float](repeating: 0, count: kBuf - 1)
        #expect(contest.renderNextBlock(&buf) == 0)
    }

    @Test func hardcodedSourceMakesPlausibleCalls() {
        let src = HardcodedCallsignSource()
        let rng = Random(seed: 3)
        for _ in 0..<100 {
            let c = src.pickCall(rng)
            #expect(c.utf8.count >= 4 && c.utf8.count <= 6)
            #expect(c.contains { $0.isNumber })
        }
    }

    @Test func callsignDbLoadsMasterDta() {
        let db = CallsignDb()
        #expect(db.pickCall(Random(seed: 1)) == "P29SX")  // empty fallback
        #expect(db.load(from: masterDtaURL()))
        #expect(db.count > 20000)
        let before = db.count
        _ = db.pickAndRemoveCall(Random(seed: 1))
        #expect(db.count == before - 1)
        #expect(!CallsignDb().load(from: masterDtaURL().appendingPathExtension("missing")))
    }
}
