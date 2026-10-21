// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Operating: the keys (KeyCommand), the entry boxes and the engine's
// events, applied through MRAppCore.OperatingState.

import AppKit
import MRAppCore
import MRScoring
import MRSimulation

extension MainWindowController {
    // MARK: - Entry boxes

    func textField(_ f: EntryField) -> EntryTextField? {
        switch f {
        case .call: callEdit
        case .rst: rstEdit
        case .nr: nrEdit
        case .other: nil
        }
    }

    /// Main.pas ActiveControl among Edit1..3.
    var activeField: EntryField {
        guard let editor = window.firstResponder as? NSText,
              let field = editor.delegate as? NSTextField else { return .other }
        if field === callEdit { return .call }
        if field === rstEdit { return .rst }
        if field === nrEdit { return .nr }
        return .other
    }

    var snapshot: EntrySnapshot {
        EntrySnapshot(call: callEdit.stringValue, rst: rstEdit.stringValue, nr: nrEdit.stringValue,
                      focus: activeField)
    }

    /// ActiveControl := field. No OnEnter when it already has the focus.
    func focus(_ f: EntryField) {
        guard let field = textField(f), activeField != f else { return }
        window.makeFirstResponder(field)
    }

    /// OnEnter (Edit1Enter / Edit2Enter).
    func entryFocused(_ f: EntryField) {
        apply(op.focusEntered(f, snapshot))
    }

    private func select(_ f: EntryField, _ range: NSRange) {
        guard let editor = textField(f)?.currentEditor() else { return }
        editor.selectedRange = range
    }

    /// Carries out what OperatingState decided.
    func apply(_ actions: [OperatingAction]) {
        for a in actions {
            switch a {
            case .send(let m, let callField):
                engine.send(m, callField: callField)
            case .save(let call, let rst, let nr):
                logQso(call: call, rst: rst, nr: nr)
            case .beep:
                beep()
            case .setText(let f, let text):
                textField(f)?.stringValue = text
            case .focus(let f):
                focus(f)
            case .selectInCall(let loc, let len):
                select(.call, NSRange(location: loc, length: len))
            case .selectInRst(let loc, let len):
                select(.rst, NSRange(location: loc, length: len))
            case .updateCallInMessage(let text):
                engine.editCall(text)
            case .abortSend:
                engine.abortSend()
            }
        }
    }

    /// Log.SaveQso past its gate: the entry gets the sim's block time,
    /// then LastQsoToScreen and the stats; Tst bumps Me.NR and looks for
    /// the DX's record (which may arrive as engineQsoTruth).
    private func logQso(call: String, rst: Int, nr: Int) {
        let generation = runGeneration
        let hst = runMode == .hst
        let logged = String(call.filter { $0 != "?" })
        engine.logQso(logged) { [weak self] seconds in
            guard let self, self.runGeneration == generation else { return }
            self.log.add(t: seconds, call: call, rst: rst, nr: nr, hstMode: hst)
            self.showLastQso(replace: false)
        }
    }

    func showLastQso(replace: Bool) {
        guard !log.isEmpty else { return }
        let row = log.formatRow(log.qsos.count - 1, sentRst: 599)  // Tst.Me.Rst
        if replace { logView.replaceLastRow(row) } else { logView.appendRow(row) }
        let hst = runMode == .hst
        var model = scoreTable.model
        model.update(log.stats(hstMode: hst), hst: hst)
        scoreTable.model = model
        histogram.bins = log.histogram()
    }

    // MARK: - KeyPreview (FormKeyDown / FormKeyPress)

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }

    /// True when the key was the form's.
    func handleKey(_ e: NSEvent) -> Bool {
        let key = e.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        let mods = Self.modifiers(e.modifierFlags.intersection(.deviceIndependentFlagsMask))
        guard let cmd = KeyCommand.map(key: key, characters: e.characters ?? "", modifiers: mods) else {
            return false
        }
        perform(cmd)
        return true
    }

    func perform(_ cmd: KeyCommand) {
        switch cmd {
        case .hisCallAndNr: apply(op.sendHisCallAndNr(snapshot))
        case .enter(let force): apply(op.processEnter(snapshot, forceSave: force))
        case .wipe: apply(op.wipeBoxes(snapshot))
        case .rit(let d): incRit(d)
        case .bandwidth(let d):
            if runMode != .hst { setBandwidth(index: bwCombo.indexOfSelectedItem + d) }
        case .speedUp: incSpeed()
        case .speedDown: decSpeed()
        case .abort: apply(op.escape())
        case .tuAndSave: apply(op.tuAndSave(snapshot))
        case .space: apply(op.processSpace(snapshot))
        case .cq: apply(op.send(.cq, snapshot))
        case .ignore: break
        }
    }
}

// MARK: - Engine events (Tst → MainForm)

extension MainWindowController: EngineEvents {
    func engineClock(seconds: Double) {
        // Panel2.Caption; ShowRate while running.
        elapsed = seconds
        clockPanel.caption = Captions.clock(seconds: seconds)
        if runMode != .stop, let r = log.rate(now: seconds) {
            ratePanel.caption = Captions.rate(r)
        }
    }

    func enginePileUpCount(_ n: Int) {
        if runMode == .pileUp { modePanel.caption = Captions.pileUp(n) }
    }

    /// DataToLastQso → CheckErr → replace the last row.
    func engineQsoTruth(call: String, rst: Int, nr: Int) {
        if log.applyTruth(call: call, trueRst: rst, trueNr: nr) {
            showLastQso(replace: true)
        }
    }

    func enginePieceFinished() { apply(op.advance(snapshot)) }

    func engineCallEditResult(applied: Bool) { op.callEditResult(applied: applied) }

    func engineSendAborted(hadHisCall: Bool, hadNr: Bool) {
        op.abortResult(hadHisCall: hadHisCall, hadNr: hadNr)
    }

    func engineContestEnded(mode: RunMode, stoppedByUser: Bool) {
        run(.stop)
        contestEnded(mode: mode, stoppedByUser: stoppedByUser)
    }
}
