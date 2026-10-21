// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit
import MRAppCore
@testable import MorseRunner
import MRPersistence
import MRScoring
import MRSimulation
import Testing

@MainActor
@Suite(.serialized)
struct ControllerTests {
    // MARK: Startup

    @Test func launchConfiguresTheEngineOnceAndWritesNothing() {
        let h = Harness(stored: [Settings.Key.wpm: 35, Settings.Key.activity: 5])
        defer { h.cleanUp() }
        #expect(h.engine.calls.count == 1)
        guard case .configure(let s) = h.engine.calls.first else {
            Issue.record("expected a single configure")
            return
        }
        #expect(s.wpm == 35 && s.activity == 5)
        #expect(h.controller.wpmSpin.value == 35)
        #expect(h.storedKeys == [Settings.Key.wpm, Settings.Key.activity])
    }

    @Test(arguments: [575, 650, 50, 500])
    func storedBandwidthKeepsUiAndEngineInStep(_ hz: Int) {
        let h = Harness(stored: [Settings.Key.bandwidth: hz])
        defer { h.cleanUp() }
        guard case .configure(let s) = h.engine.calls.first else {
            Issue.record("expected configure")
            return
        }
        let c = h.controller
        #expect(c.bwCombo.titleOfSelectedItem == "\(s.rxBandwidthHz) Hz")
        #expect(c.rit.bandwidthHz == s.rxBandwidthHz)
        #expect(BandwidthTable.index(hz: s.rxBandwidthHz) != nil)
    }

    // MARK: Monitor level

    @Test func monitorLevelIsPersisted() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.monMenu(menuItem(tag: -20))
        #expect(abs(h.settings.load().monitorLevel - 2.0 / 3.0) < 1e-6)
        #expect(h.engine.calls.last == .monitorLevel(MonitorLevel.menuValue(tag: -20)))
        #expect(h.controller.volume.toolTip == "-20 dB")
    }

    @Test func monitorLevelLoadsWithoutTheRemap() {
        let h = Harness(stored: [Settings.Key.monitor: 0.5])
        defer { h.cleanUp() }
        #expect(h.controller.volume.value == 0.5)
        #expect(h.controller.volume.toolTip == "-30.0 dB")
    }

    // MARK: Sending and ESM

    @Test func fKeyButtonsSendTheirMessages() {
        let h = Harness()
        defer { h.cleanUp() }
        for b in h.controller.fKeys { h.controller.fKeyClicked(b) }
        #expect(h.engine.sent == MenuSpec.sendItems.map(\.message))
    }

    @Test func sendMenuCarriesTheCallField() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.callEdit.stringValue = "K1ABC"
        h.controller.sendMenu(menuItem(tag: Message.hisCall.rawValue))
        #expect(h.engine.calls.last == .send(.hisCall, "K1ABC"))
        #expect(h.controller.op.callSent)
    }

    @Test func enterWalksTheEsmAndSavesWithTheSimTime() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.run(.pileUp)
        h.engine.calls.removeAll()
        #expect(c.handleKey(h.key("\r")))
        #expect(h.engine.sent == [.cq])
        c.callEdit.stringValue = "K1ABC"
        _ = c.handleKey(h.key("\r"))
        #expect(h.engine.sent == [.cq, .hisCall, .nr])
        #expect(c.op.mustAdvance)
        c.rstEdit.stringValue = "599"
        c.nrEdit.stringValue = "12"
        h.engine.blockSeconds = 125
        _ = c.handleKey(h.key("\r"))
        #expect(h.engine.sent == [.cq, .hisCall, .nr, .tu])
        #expect(h.engine.calls.contains(.logQso("K1ABC")))
        #expect(c.log.qsos.count == 1)
        #expect(c.log.qsos.first?.t == 125)
        #expect(c.callEdit.stringValue.isEmpty && c.rstEdit.stringValue.isEmpty && c.nrEdit.stringValue.isEmpty)
        // WipeBoxes ran Edit1Change for the emptied call.
        #expect(h.engine.calls.contains(.editCall("")))
        #expect(c.logView.text.contains("K1ABC"))
        #expect(c.histogram.bins[0] == 1)
    }

    @Test func truthReplacesTheLastRow() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.run(.pileUp)
        c.callEdit.stringValue = "K1ABC"
        c.rstEdit.stringValue = "599"
        c.nrEdit.stringValue = "7"
        c.perform(.enter(forceSave: true))
        #expect(c.logView.text.hasSuffix("NIL"))
        c.engineQsoTruth(call: "K1ABC", rst: 599, nr: 7)
        #expect(c.log.qsos.first?.err == "   ")
        #expect(c.scoreTable.model.verifiedScore == "1")
        #expect(c.logView.text.components(separatedBy: "\n").count == 2)
    }

    @Test func saveGateBeeps() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.callEdit.stringValue = "K1"
        h.controller.perform(.enter(forceSave: true))
        #expect(h.beeps == 1)
        #expect(h.controller.log.isEmpty)
    }

    @Test func staleSaveAnswerIsDroppedAfterANewRun() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.run(.pileUp)
        let generation = c.runGeneration
        c.run(.stop)
        c.run(.single)
        #expect(c.runGeneration == generation + 1)
    }

    @Test func emptiedCallStillUpdatesTheMessage() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.callEdit.stringValue = ""
        c.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: c.callEdit))
        #expect(h.engine.calls.last == .editCall(""))
    }

    @Test func escapeAbortsAndClearsFlagsFromTheAnswer() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.callEdit.stringValue = "K1ABC"
        c.perform(.hisCallAndNr)
        #expect(c.handleKey(h.key("\u{1b}")))
        #expect(h.engine.calls.last == .abortSend)
        c.engineSendAborted(hadHisCall: true, hadNr: false)
        #expect(!c.op.callSent && c.op.nrSent)
    }

    // MARK: Keys

    @Test func keysAreMappedWithoutKeyCodes() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.callEdit.stringValue = "K1ABC"
        // Ctrl-W (keyCode 0 here: no layout dependence).
        #expect(c.handleKey(h.key("\u{17}", ignoring: "w", .control)))
        #expect(c.callEdit.stringValue.isEmpty)
        c.callEdit.stringValue = "K1ABC"
        #expect(c.handleKey(h.key("∑", ignoring: "w", .option)))
        #expect(c.callEdit.stringValue.isEmpty)
        #expect(!c.handleKey(h.key("q", .command)))
        #expect(!c.handleKey(h.key("k")))
    }

    @Test func ritAndSpeedKeys() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        _ = c.handleKey(h.functionKey(FunctionKey.upArrow))
        _ = c.handleKey(h.functionKey(FunctionKey.upArrow))
        #expect(c.ritHz == 100 && c.rit.ritHz == 100)
        #expect(h.engine.calls.last == .rit(100))
        let wpm = c.wpmSpin.value
        _ = c.handleKey(h.functionKey(FunctionKey.pageUp))
        #expect(c.wpmSpin.value == SpeedStep.up(wpm))
        #expect(h.settings.load().wpm == SpeedStep.up(wpm))
        let bw = c.bwCombo.indexOfSelectedItem
        _ = c.handleKey(h.functionKey(FunctionKey.downArrow, .command))
        #expect(c.bwCombo.indexOfSelectedItem == bw - 1)
        // Plain F9 is swallowed and does nothing.
        let before = h.engine.calls.count
        #expect(c.handleKey(h.functionKey(FunctionKey.f9)))
        #expect(h.engine.calls.count == before)
    }

    // MARK: Run modes

    @Test(arguments: [RunMode.pileUp, .single, .wpx, .hst])
    func runEnablesAndDisables(_ m: RunMode) {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.run(m)
        let rules = RunModeRules.controls(for: m, competitionDuration: c.competitionDuration)
        #expect(c.runMode == m)
        #expect(!c.myCallEdit.isEnabled && !c.durationSpin.isEnabled)
        #expect(c.runItems.allSatisfy { !$0.isEnabled } && c.popupRunItems.allSatisfy { !$0.isEnabled })
        #expect(c.stopItem.isEnabled && c.popupStopItem.isEnabled)
        #expect(c.conditionChecks.allSatisfy { $0.isEnabled == rules.conditionsEnabled })
        #expect(c.conditionItems.allSatisfy { $0.isEnabled == rules.conditionsEnabled })
        #expect(c.activitySpin.isEnabled == (m != .hst))
        #expect(c.bwCombo.isEnabled == (m != .hst))
        #expect(c.scoreTable.tableVisible == (m != .hst))
        #expect(!c.logView.isHidden && c.splash.isHidden)
        #expect(h.engine.calls.last == .runMode(m))
        // F8 now belongs to Send › NIL.
        #expect(c.runItems[0].keyEquivalent.isEmpty)
        c.engineContestEnded(mode: m, stoppedByUser: true)
        #expect(c.runMode == .stop)
        #expect(c.runItems.allSatisfy { $0.isEnabled })
        #expect(!c.runItems[0].keyEquivalent.isEmpty)
        #expect(c.modePanel.caption.isEmpty)
    }

    @Test func wpxForcesConditionsAndDurationAndPersistsThem() {
        let h = Harness(stored: [Settings.Key.qrn: false, Settings.Key.duration: 10,
                                 Settings.Key.competitionDuration: 45])
        defer { h.cleanUp() }
        h.controller.run(.wpx)
        let s = h.settings.load()
        #expect(s.qrn && s.qrm && s.qsb && s.flutter && s.lids)
        #expect(s.durationMinutes == 45)
        #expect(h.controller.durationSpin.value == 45)
        #expect(h.controller.modePanel.caption == "COMPETITION")
    }

    @Test func hstForcesActivityBandwidthAndClearsConditions() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.run(.hst)
        let s = h.settings.load()
        #expect(!s.qrn && !s.qrm && !s.qsb && !s.flutter && !s.lids)
        #expect(s.activity == 4 && s.bandwidthHz == 600)
        #expect(c.activitySpin.value == 4)
        #expect(c.bwCombo.indexOfSelectedItem == 10)
        #expect(c.rit.bandwidthHz == 600)
        // Ctrl-Up / Down are ignored in HST.
        c.perform(.bandwidth(-1))
        #expect(c.bwCombo.indexOfSelectedItem == 10)
        #expect(c.scoreTable.hstCaption == "0")
    }

    @Test func runningTheSameModeIsANoOp() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.run(.pileUp)
        let n = h.engine.calls.count
        h.controller.run(.pileUp)
        #expect(h.engine.calls.count == n)
    }

    @Test func f8FollowsTheRunState() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        let f8 = h.functionKey(FunctionKey.f8)
        #expect(c.mainMenu.performKeyEquivalent(with: f8))
        #expect(c.runMode == .pileUp)
        h.engine.calls.removeAll()
        #expect(c.mainMenu.performKeyEquivalent(with: f8))
        #expect(h.engine.sent == [.nilMsg])
        #expect(c.runMode == .pileUp)
    }

    @Test func recordingOpensAtRunWhenEnabled() {
        let h = Harness(stored: [Settings.Key.saveWav: true])
        defer { h.cleanUp() }
        h.controller.run(.single)
        #expect(h.engine.calls.contains(.recording(h.controller.files.recording)))
        h.controller.run(.stop)
        #expect(h.engine.calls.contains(.recording(nil)))
    }

    @Test func fileMenuFollowsTheRunState() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.menuNeedsUpdate(c.fileMenu)
        #expect(c.audioRecordingItem.isEnabled)
        #expect(!c.playRecordingItem.isEnabled)  // no recording yet
        c.toggleRecording()
        c.menuNeedsUpdate(c.fileMenu)
        #expect(c.audioRecordingItem.state == .on)
        #expect(h.settings.load().saveWav)
        c.run(.pileUp)
        c.menuNeedsUpdate(c.fileMenu)
        #expect(!c.audioRecordingItem.isEnabled)
    }

    @Test func settingsMenuMirrorsTheCheckboxes() {
        let h = Harness(stored: [Settings.Key.qsb: false])
        defer { h.cleanUp() }
        let c = h.controller
        c.menuNeedsUpdate(c.settingsMenu)
        #expect(c.conditionItems.map(\.state) == c.conditionChecks.map(\.state))
        c.conditionMenu(c.conditionItems[2])
        #expect(c.qsbCheck.state == .on)
        #expect(h.settings.load().qsb)
    }

    // MARK: End of contest and files

    @Test func wpxEndWritesTheStampedLineAndHiScore() throws {
        let h = Harness(stored: [Settings.Key.call: "kf5o", Settings.Key.hiScore: 0])
        defer { h.cleanUp() }
        let c = h.controller
        c.myCallEdit.stringValue = "KF5O "
        c.run(.wpx)
        c.callEdit.stringValue = "K1ABC"
        c.rstEdit.stringValue = "599"
        c.nrEdit.stringValue = "1"
        c.perform(.enter(forceSave: true))
        c.engineQsoTruth(call: "K1ABC", rst: 599, nr: 1)
        c.engineContestEnded(mode: .wpx, stoppedByUser: false)
        let text = try #require(c.files.scoreListContents())
        #expect(text.hasPrefix("2026-03-04 KF5O 1 1 ["))
        #expect(h.scoreDialogs.count == 1 && h.scoreDialogs[0].1)
        #expect(h.settings.load().hiScore == 1)
    }

    @Test func userStoppedWpxPopsNothing() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.run(.wpx)
        h.controller.engineContestEnded(mode: .wpx, stoppedByUser: true)
        #expect(h.scoreDialogs.isEmpty && h.messages.isEmpty)
        #expect(h.controller.files.scoreListContents() == nil)
    }

    @Test func hstEndAlwaysPops() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.run(.hst)
        h.controller.engineContestEnded(mode: .hst, stoppedByUser: true)
        #expect(h.messages == ["HST Score: 0"])
        let line = try String(contentsOf: h.controller.files.hstResults, encoding: .utf8)
        #expect(line.hasPrefix("2026-03-04 05:06\t"))
    }

    @Test func viewScoreTableMidRunDoesNotEatTheList() throws {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        try c.files.append("2026-01-01 KF5O 1 1 [00000000]", to: c.files.scoreList)
        c.run(.pileUp)
        c.callEdit.stringValue = "K1ABC"
        c.rstEdit.stringValue = "599"
        c.nrEdit.stringValue = "1"
        c.perform(.enter(forceSave: true))
        c.viewScoreTable()
        c.engineQsoTruth(call: "K1ABC", rst: 599, nr: 1)
        #expect(c.logView.text.hasPrefix("2026-01-01 KF5O 1 1 [00000000]"))
    }

    @Test func emptyScoreTableMessage() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.viewScoreTable()
        #expect(h.controller.logView.text == "Your score table is empty")
    }

    @Test func webPagesUseHttps() {
        let h = Harness()
        defer { h.cleanUp() }
        h.controller.viewHiScorePage()
        h.controller.webPage()
        #expect(h.opened.map(\.scheme) == ["https", "https"])
    }

    // MARK: Clock

    @Test func clockAndRateCaptions() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        c.engineClock(seconds: 3_661.2)
        #expect(c.clockPanel.caption == "01:01:01")
        #expect(c.ratePanel.caption.isEmpty)  // stopped: no ShowRate
        c.run(.pileUp)
        c.engineClock(seconds: 60)
        #expect(c.ratePanel.caption == "0  qso/hr.")
        c.enginePileUpCount(3)
        #expect(c.modePanel.caption == "Pile-Up:  3")
    }
}

@MainActor
private func menuItem(tag: Int) -> NSMenuItem {
    let i = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    i.tag = tag
    return i
}
