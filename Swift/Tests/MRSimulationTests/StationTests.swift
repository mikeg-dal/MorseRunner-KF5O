// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Ports of tests/simulation/test_station.cpp, test_qrn_qrm.cpp and
// test_station_collection.cpp.

import MRCore
@testable import MRSimulation
import Testing

@Suite struct StationTests {
    @Test func dxStationConstructsWithRandomizedParams() {
        let eng = FakeEngine(seed: 42)
        let dx = DxStation(engine: eng, call: "W1AW")
        #expect(dx.myCall == "W1AW")
        #expect(dx.hisCall == eng.myCallsign)
        #expect(dx.wpm >= 15)  // pile-up: ≥ half of 30
        #expect(dx.wpm <= 30)
        #expect(dx.amplitude >= 9000)
        #expect(dx.state == .copying)
    }

    @Test func dxStationGetBlockEmptyWhenNotSending() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        dx.setTimeout(kNeverTimeout)
        var buf = [Float](repeating: 0, count: 64)
        #expect(dx.getBlock(&buf) == 0)
    }

    @Test func myStationDefaultsMatchPascal() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        #expect(me.myCall == "VE3NEA")
        #expect(me.nr == 1)
        #expect(me.rst == 599)
        #expect(me.pitchHz == 600)
        #expect(me.wpm == 30)
    }

    @Test func myStationSendCqGeneratesEnvelope() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        me.setMyCall("KF5O")
        me.sendMsg(.cq)
        #expect(me.state == .sending)
        var buf = [Float](repeating: 0, count: 512)
        me.getBlock(&buf)
        #expect(buf.contains { $0 != 0 })
    }

    @Test func myStationSplitsPiecesAroundHisCall() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        me.setHisCall("JA1ABC")
        me.sendMsg(.hisCall)
        #expect(me.state == .sending)
        #expect(me.pieceCount == 1)
        me.sendMsg(.nr)
        #expect(me.pieceCount == 2)
    }

    @Test func myStationAbortMarksGarbage() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        me.sendMsg(.cq)
        me.abortSend()
        #expect(me.state == .listening)
        #expect(me.msg.contains(.garbage))
    }

    @Test func bfoPhaseAdvancesPerSample() {
        let eng = FakeEngine()
        let me = MyStation(engine: eng)
        me.setPitchHz(600)
        let p0 = me.tickBfoPhase()
        let p1 = me.tickBfoPhase()
        #expect(p1 > p0)
    }

    @Test func timeoutTickFiresEvent() {
        let eng = FakeEngine()
        let dx = DxStation(engine: eng, call: "W1AW")
        dx.setTimeout(3)
        dx.tick()
        #expect(dx.timeout == 2)
        dx.tick()
        #expect(dx.timeout == 1)
        // Third tick fires the Timeout event in processEvent.
        dx.tick()
        #expect(dx.timeout == 0)
    }
}

@Suite struct QrnQrmTests {
    @Test func qrnConstructsInSendingState() {
        let eng = FakeEngine(seed: 7)
        let qrn = QrnStation(engine: eng)
        #expect(qrn.state == .sending)
    }

    @Test func qrnFinishesAfterEnvelopeExhausted() {
        let eng = FakeEngine(seed: 123)
        let qrn = QrnStation(engine: eng)
        #expect(!qrn.isFinished)
        var buf = [Float](repeating: 0, count: 512)
        for _ in 0..<10000 where !qrn.isFinished {
            qrn.getBlock(&buf)
            qrn.tick()
        }
        #expect(qrn.isFinished)
    }

    @Test func qrmConstructsInSendingState() {
        let eng = FakeEngine(seed: 5)
        let qrm = QrmStation(engine: eng, call: "JA1XYZ")
        #expect(qrm.state == .sending)
        #expect(qrm.myCall == "JA1XYZ")
        #expect(qrm.hisCall == eng.myCallsign)
        // Pascal: Wpm in [30, 50), Amplitude in [5000, 30000).
        #expect(qrm.wpm >= 30 && qrm.wpm < 50)
        #expect(qrm.amplitude >= 5000 && qrm.amplitude < 30000)
    }

    @Test func qrmFinishesAfterPatienceRunsOut() {
        let eng = FakeEngine(seed: 99)
        let qrm = QrmStation(engine: eng, call: "JA1XYZ")
        for _ in 0..<6 where !qrm.isFinished {
            qrm.processEvent(.msgSent)
        }
        #expect(qrm.isFinished)
    }

    @Test func qrmIgnoresMeStartedAndMeFinished() {
        let eng = FakeEngine(seed: 99)
        let qrm = QrmStation(engine: eng, call: "JA1XYZ")
        let before = qrm.state
        qrm.processEvent(.meStarted)
        qrm.processEvent(.meFinished)
        #expect(qrm.state == before)
        #expect(!qrm.isFinished)
    }
}

@Suite struct StationCollectionTests {
    @Test func factoriesAddItems() {
        let eng = FakeEngine(seed: 1)
        let sc = StationCollection()
        sc.addCaller(eng, "W1AW")
        sc.addQrn(eng)
        sc.addQrm(eng, "JA1XYZ")
        #expect(sc.count == 3)
    }

    @Test func dxCountTracksOnlyDxStations() {
        let eng = FakeEngine(seed: 1)
        let sc = StationCollection()
        sc.addCaller(eng, "W1AW")
        sc.addCaller(eng, "K2ABC")
        sc.addQrn(eng)
        sc.addQrm(eng, "JA1XYZ")
        #expect(sc.dxCount == 2)
    }

    @Test func sweepRemovesFinishedQrnStations() {
        let eng = FakeEngine(seed: 2)
        let sc = StationCollection()
        sc.addCaller(eng, "W1AW")
        let qrn = sc.addQrn(eng)
        #expect(sc.count == 2)
        qrn.processEvent(.msgSent)
        sc.sweep()
        #expect(sc.count == 1)
    }

    @Test func sweepRemovesFailedDxStation() {
        let eng = FakeEngine(seed: 3)
        let sc = StationCollection()
        let dx = sc.addCaller(eng, "W1AW")
        dx.dxOperator.setState(.failed)
        #expect(dx.isFinished)
        sc.sweep()
        #expect(sc.count == 0)
    }

    @Test func sweepRemovesReleasedDoneDxStation() {
        let eng = FakeEngine(seed: 3)
        let sc = StationCollection()
        let dx = sc.addCaller(eng, "W1AW")
        dx.dxOperator.setState(.done)
        sc.sweep()
        #expect(sc.count == 1)  // Done stays until released
        dx.release()
        sc.sweep()
        #expect(sc.count == 0)
    }

    @Test func sweepKeepsLivingStations() {
        let eng = FakeEngine(seed: 4)
        let sc = StationCollection()
        sc.addCaller(eng, "W1AW")
        sc.addCaller(eng, "K2ABC")
        sc.sweep()
        #expect(sc.count == 2)
    }

    @Test func clearRemovesAll() {
        let eng = FakeEngine()
        let sc = StationCollection()
        sc.addQrn(eng)
        sc.addQrn(eng)
        sc.clear()
        #expect(sc.isEmpty)
    }
}
