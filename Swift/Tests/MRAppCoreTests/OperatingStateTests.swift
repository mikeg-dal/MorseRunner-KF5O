// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

@testable import MRAppCore
import MRSimulation
import Testing

private func state(callSent: Bool, nrSent: Bool) -> OperatingState {
    var s = OperatingState()
    let snap = EntrySnapshot(call: "X")
    if callSent { _ = s.send(.hisCall, snap) }
    if nrSent { _ = s.send(.nr, snap) }
    return s
}

private func sends(_ actions: [OperatingAction]) -> [Message] {
    actions.compactMap { if case .send(let m, _) = $0 { m } else { nil } }
}

private func wipe(callWasEmpty: Bool) -> [OperatingAction] {
    [.setText(.call, "")] + (callWasEmpty ? [] : [.updateCallInMessage("")])
        + [.setText(.rst, ""), .setText(.nr, ""), .focus(.call)]
}

struct EsmCase: Sendable, CustomTestStringConvertible {
    let c: Bool, n: Bool, r: Bool
    let expected: [Message]
    let saves: Bool
    var testDescription: String { "C=\(c) N=\(n) R=\(r)" }
}

struct OperatingStateTests {
    /// ProcessEnter's full C / N / R table (call box not empty).
    @Test(arguments: [
        EsmCase(c: false, n: false, r: false, expected: [.hisCall, .nr], saves: false),
        EsmCase(c: false, n: false, r: true, expected: [.hisCall, .nr], saves: false),
        EsmCase(c: false, n: true, r: false, expected: [.hisCall, .qm], saves: false),
        EsmCase(c: false, n: true, r: true, expected: [.hisCall, .tu], saves: true),
        EsmCase(c: true, n: false, r: false, expected: [.hisCall, .nr], saves: false),
        EsmCase(c: true, n: false, r: true, expected: [.nr, .tu], saves: true),
        EsmCase(c: true, n: true, r: false, expected: [.qm], saves: false),
        EsmCase(c: true, n: true, r: true, expected: [.tu], saves: true),
    ])
    func esmTable(_ e: EsmCase) {
        var s = state(callSent: e.c, nrSent: e.n)
        let snap = EntrySnapshot(call: "K1ABC", rst: "599", nr: e.r ? "123" : "", focus: .call)
        let out = s.processEnter(snap, forceSave: false)
        #expect(sends(out) == e.expected)
        #expect(out.contains(.save(call: "K1ABC", rst: 599, nr: 123)) == e.saves)
        #expect(s.mustAdvance == !e.saves)
        if e.saves {
            #expect(!s.callSent && !s.nrSent)  // WipeBoxes
        }
    }

    @Test func hisCallCarriesTheCallField() {
        var s = OperatingState()
        let out = s.processEnter(EntrySnapshot(call: "K1ABC"), forceSave: false)
        #expect(out.first == .send(.hisCall, callField: "K1ABC"))
        #expect(out.dropFirst().first == .send(.nr, callField: ""))
    }

    @Test func enterWithEmptyCallSendsCq() {
        var s = state(callSent: true, nrSent: true)
        let out = s.processEnter(EntrySnapshot(call: "", rst: "599", nr: "1"), forceSave: false)
        #expect(out == [.send(.cq, callField: "")])
        #expect(!s.mustAdvance)
    }

    @Test(arguments: [
        ("K1ABC", "599", "1", true), ("K1", "599", "1", false), ("K1ABC", "59", "1", false),
        ("K1ABC", "599", "", false), ("ABC", "599", "0001", true), ("K1ABC", "5999", "1", false),
    ])
    func saveGate(_ call: String, _ rst: String, _ nr: String, _ ok: Bool) {
        var s = OperatingState()
        let out = s.processEnter(EntrySnapshot(call: call, rst: rst, nr: nr), forceSave: true)
        if ok {
            #expect(out == [.save(call: call, rst: Int(rst) ?? 0, nr: Int(nr) ?? 0)]
                    + wipe(callWasEmpty: false))
        } else {
            #expect(out == [.beep])
        }
    }

    @Test func forceSaveSendsNothing() {
        var s = OperatingState()
        let out = s.processEnter(EntrySnapshot(call: "K1ABC", rst: "599", nr: "5"), forceSave: true)
        #expect(sends(out).isEmpty)
    }

    @Test func tuAndSaveSendsHisCallOnlyIfNotSent() {
        var s = OperatingState()
        let snap = EntrySnapshot(call: "K1ABC", rst: "599", nr: "5")
        #expect(sends(s.tuAndSave(snap)) == [.hisCall, .tu])
        var t = state(callSent: true, nrSent: false)
        #expect(sends(t.tuAndSave(snap)) == [.tu])
        // A failed gate still sends (Pascal sends before SaveQso beeps).
        var u = OperatingState()
        let bad = u.tuAndSave(EntrySnapshot(call: "K1ABC"))
        #expect(sends(bad) == [.hisCall, .tu])
        #expect(bad.last == .beep)
    }

    @Test func semicolonSendsHisCallAndNr() {
        var s = OperatingState()
        let out = s.sendHisCallAndNr(EntrySnapshot(call: "W1AW"))
        #expect(out == [.send(.hisCall, callField: "W1AW"), .send(.nr, callField: "")])
        #expect(s.callSent && s.nrSent)
    }

    @Test(arguments: [
        (EntryField.call, "", [OperatingAction.setText(.rst, "599"), .focus(.nr)]),
        (EntryField.rst, "", [OperatingAction.setText(.rst, "599"), .focus(.nr)]),
        (EntryField.call, "579", [OperatingAction.focus(.nr)]),
        (EntryField.nr, "", [OperatingAction.focus(.call)]),
        (EntryField.other, "", [OperatingAction.focus(.call)]),
    ])
    func space(_ focus: EntryField, _ rst: String, _ expected: [OperatingAction]) {
        var s = OperatingState()
        _ = s.processEnter(EntrySnapshot(call: "K1ABC"), forceSave: false)
        #expect(s.mustAdvance)
        #expect(s.processSpace(EntrySnapshot(call: "K1ABC", rst: rst, focus: focus)) == expected)
        #expect(!s.mustAdvance)
    }

    @Test func advanceOnlyWhenArmed() {
        var s = OperatingState()
        #expect(s.advance(EntrySnapshot(call: "K1ABC")).isEmpty)
        _ = s.processEnter(EntrySnapshot(call: "K1ABC"), forceSave: false)
        #expect(s.advance(EntrySnapshot(call: "K1ABC")) == [.setText(.rst, "599"), .focus(.nr)])
        #expect(!s.mustAdvance)
        #expect(s.advance(EntrySnapshot(call: "K1ABC")).isEmpty)
    }

    @Test(arguments: [
        ("K1?BC", EntryField.call, [OperatingAction.selectInCall(location: 2, length: 1)]),
        ("K1?BC", EntryField.nr, [OperatingAction.focus(.call)]),
        ("?1ABC", EntryField.call, [OperatingAction]()),  // Pos = 1: not selected
        ("K1ABC", EntryField.call, [OperatingAction.focus(.nr)]),
    ])
    func advanceWithQuestionMark(_ call: String, _ focus: EntryField, _ tail: [OperatingAction]) {
        var s = OperatingState()
        _ = s.processEnter(EntrySnapshot(call: call), forceSave: false)
        let out = s.advance(EntrySnapshot(call: call, rst: "599", focus: focus))
        #expect(out == tail)
    }

    @Test(arguments: [
        (EntryField.call, "AB?C", "", [OperatingAction.selectInCall(location: 2, length: 1)]),
        (EntryField.call, "?ABC", "", [OperatingAction]()),
        (EntryField.call, "ABC", "", [OperatingAction]()),
        (EntryField.rst, "", "599", [OperatingAction.selectInRst(location: 1, length: 1)]),
        (EntryField.rst, "", "59", [OperatingAction]()),
        (EntryField.nr, "A?", "599", [OperatingAction]()),
    ])
    func focusEntered(_ f: EntryField, _ call: String, _ rst: String, _ expected: [OperatingAction]) {
        let s = OperatingState()
        #expect(s.focusEntered(f, EntrySnapshot(call: call, rst: rst, focus: f)) == expected)
    }

    @Test func edit1ChangeAlwaysUpdatesTheMessage() {
        var s = state(callSent: true, nrSent: true)
        // Pascal calls UpdateCallInMessage even for an empty call.
        #expect(s.callEdited("") == [.updateCallInMessage("")])
        #expect(!s.nrSent)
        #expect(s.callSent)  // until the answer says otherwise
        s.callEditResult(applied: false)
        #expect(!s.callSent)

        var t = state(callSent: true, nrSent: true)
        #expect(t.callEdited("K1AB") == [.updateCallInMessage("K1AB")])
        #expect(t.nrSent)
        t.callEditResult(applied: true)
        #expect(t.callSent)
    }

    @Test func staleEditAnswersDoNotClearAFreshHisCall() {
        var s = OperatingState()
        _ = s.callEdited("K1A")
        _ = s.callEdited("K1AB")
        _ = s.send(.hisCall, EntrySnapshot(call: "K1AB"))
        s.callEditResult(applied: false)
        s.callEditResult(applied: false)
        #expect(s.callSent)
        // A later edit's answer counts again.
        _ = s.callEdited("K1ABC")
        s.callEditResult(applied: false)
        #expect(!s.callSent)
    }

    @Test func wipeTriggersEdit1ChangeOnlyWhenTheCallChanges() {
        var s = state(callSent: true, nrSent: true)
        #expect(s.wipeBoxes(EntrySnapshot(call: "K1ABC", rst: "599", nr: "1"))
                == wipe(callWasEmpty: false))
        #expect(!s.callSent && !s.nrSent)
        var t = OperatingState()
        #expect(t.wipeBoxes(EntrySnapshot()) == wipe(callWasEmpty: true))
    }

    @Test func wipeAnswerArrivingLateKeepsFlagsClear() {
        var s = state(callSent: true, nrSent: true)
        _ = s.wipeBoxes(EntrySnapshot(call: "K1ABC"))
        s.callEditResult(applied: true)
        #expect(!s.callSent)
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func escape(_ his: Bool, _ nr: Bool) {
        var s = state(callSent: true, nrSent: true)
        #expect(s.escape() == [.abortSend])
        s.abortResult(hadHisCall: his, hadNr: nr)
        #expect(s.callSent == !his)
        #expect(s.nrSent == !nr)
    }

    @Test func enterAfterEnterCompletesTheQso() {
        // The ESM walk: Enter (call) → his+nr; Enter (nr typed) → TU + save.
        var s = OperatingState()
        _ = s.processEnter(EntrySnapshot(call: "K1ABC"), forceSave: false)
        let out = s.processEnter(EntrySnapshot(call: "K1ABC", rst: "599", nr: "12"), forceSave: false)
        #expect(sends(out) == [.tu])
        #expect(out.contains(.save(call: "K1ABC", rst: 599, nr: 12)))
    }
}
