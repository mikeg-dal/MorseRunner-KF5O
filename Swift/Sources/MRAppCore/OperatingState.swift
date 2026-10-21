// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The operating logic of Main.pas and Log.pas (GUI half) as a reducer:
// SendMsg, ProcessEnter (ESM), ProcessSpace, the FormKeyPress keys,
// Edit1Change, Edit1Enter / Edit2Enter, WipeBoxes, Advance and SaveQso's
// gate. It owns Log.CallSent / Log.NrSent / MustAdvance and returns the
// actions the window applies (send to Tst, log, beep, move the focus...).
//
// One difference is structural: Tst.Me lives on the simulation thread,
// so UpdateCallInMessage's result and the Esc abort's Me.Msg flags come
// back later (callEditResult / abortResult) instead of synchronously.

import Foundation
import MRSimulation

/// Edit1 / Edit2 / Edit3, or anything else (ActiveControl elsewhere).
public enum EntryField: Sendable, Equatable {
    case call, rst, nr, other
}

/// What the three entry boxes hold, and which has the focus.
public struct EntrySnapshot: Sendable, Equatable {
    public var call: String
    public var rst: String
    public var nr: String
    public var focus: EntryField

    public init(call: String = "", rst: String = "", nr: String = "", focus: EntryField = .call) {
        self.call = call
        self.rst = rst
        self.nr = nr
        self.focus = focus
    }
}

public enum OperatingAction: Sendable, Equatable {
    /// Tst.Me.SendMsg; for msgHisCall `callField` is Edit1.Text.
    case send(Message, callField: String)
    /// Log.SaveQso passed its gate: log this entry (then the stats, the
    /// log row and Inc(Tst.Me.NR) follow in the window / engine).
    case save(call: String, rst: Int, nr: Int)
    case beep
    /// A programmatic Text := assignment (does not re-enter Edit1Change).
    case setText(EntryField, String)
    /// ActiveControl := field. The window reports the focus change back
    /// through focusEntered(_:in:).
    case focus(EntryField)
    /// Edit1Enter: select the '?' at this UTF-16 offset.
    case selectInCall(location: Int, length: Int)
    /// Edit2Enter: select the middle digit of a 3-character RST.
    case selectInRst(location: Int, length: Int)
    /// Tst.Me.UpdateCallInMessage(text); the result comes back through
    /// callEditResult(applied:).
    case updateCallInMessage(String)
    /// Tst.Me.AbortSend; the Me.Msg flags come back through abortResult.
    case abortSend
}

public struct OperatingState: Sendable, Equatable {
    /// Log.CallSent / Log.NrSent.
    public private(set) var callSent = false
    public private(set) var nrSent = false
    /// Main.pas MustAdvance.
    public private(set) var mustAdvance = false
    /// UpdateCallInMessage requests still on their way to the sim thread,
    /// and how many of their answers predate the last msgHisCall (and so
    /// must not clear the CallSent it set).
    private var pendingCallEdits = 0
    private var staleCallEdits = 0

    public init() {}

    // MARK: Sending

    /// TMainForm.SendMsg (SendClick does the same through it).
    public mutating func send(_ m: Message, _ s: EntrySnapshot) -> [OperatingAction] {
        if m == .hisCall {
            callSent = true
            staleCallEdits = pendingCallEdits
        }
        if m == .nr { nrSent = true }
        return [.send(m, callField: m == .hisCall ? s.call : "")]
    }

    /// ';' and Insert: <his> <#>.
    public mutating func sendHisCallAndNr(_ s: EntrySnapshot) -> [OperatingAction] {
        send(.hisCall, s) + send(.nr, s)
    }

    /// '.', '+', '[', ',': TU & save.
    public mutating func tuAndSave(_ s: EntrySnapshot) -> [OperatingAction] {
        var out: [OperatingAction] = []
        if !callSent { out += send(.hisCall, s) }
        out += send(.tu, s)
        out += saveQso(s)
        return out
    }

    // MARK: ESM

    /// TMainForm.ProcessEnter. `forceSave`: Ctrl, Shift or Alt held.
    public mutating func processEnter(_ s: EntrySnapshot, forceSave: Bool) -> [OperatingAction] {
        mustAdvance = false
        if forceSave { return saveQso(s) }
        // No QSO in progress: CQ.
        if s.call.isEmpty { return send(.cq, s) }

        let c = callSent, n = nrSent, r = !s.nr.isEmpty
        var out: [OperatingAction] = []
        // His call if not sent before, or if the call changed.
        if !c || (!n && !r) { out += send(.hisCall, s) }
        if !n { out += send(.nr, s) }
        if n && !r { out += send(.qm, s) }
        if r && (c || n) {
            out += send(.tu, s)
            out += saveQso(s)
        } else {
            mustAdvance = true
        }
        return out
    }

    /// TMainForm.ProcessSpace.
    public mutating func processSpace(_ s: EntrySnapshot) -> [OperatingAction] {
        mustAdvance = false
        switch s.focus {
        case .call, .rst:
            var out: [OperatingAction] = []
            if s.rst.isEmpty { out.append(.setText(.rst, "599")) }
            out.append(.focus(.nr))
            return out
        case .nr, .other:
            return [.focus(.call)]
        }
    }

    /// TMainForm.Advance, run when a piece of the player's message ends.
    public mutating func advance(_ s: EntrySnapshot) -> [OperatingAction] {
        guard mustAdvance else { return [] }
        var out: [OperatingAction] = []
        if s.rst.isEmpty { out.append(.setText(.rst, "599")) }
        if !s.call.contains("?") {
            out.append(.focus(.nr))
        } else if s.focus == .call {
            out += Self.edit1Enter(s.call)
        } else {
            out.append(.focus(.call))
        }
        mustAdvance = false
        return out
    }

    // MARK: Log.SaveQso

    /// The GUI half of Log.SaveQso: the gate (call ≥ 3 characters, RST
    /// exactly 3, NR not empty, else Beep), then the entry and WipeBoxes.
    public mutating func saveQso(_ s: EntrySnapshot) -> [OperatingAction] {
        guard s.call.count >= 3, s.rst.count == 3, !s.nr.isEmpty else { return [.beep] }
        return [.save(call: s.call, rst: Int(s.rst) ?? 0, nr: Int(s.nr) ?? 0)] + wipeBoxes(s)
    }

    /// TMainForm.WipeBoxes. Edit1.Text := '' fires Edit1Change when the
    /// text changes (TControl.SetText skips an unchanged value).
    public mutating func wipeBoxes(_ s: EntrySnapshot) -> [OperatingAction] {
        var out: [OperatingAction] = [.setText(.call, "")]
        if !s.call.isEmpty { out += callEdited("") }
        out += [.setText(.rst, ""), .setText(.nr, ""), .focus(.call)]
        callSent = false
        nrSent = false
        return out
    }

    // MARK: Edit events

    /// TMainForm.Edit1Change: an empty call clears NrSent; the text goes
    /// to Tst.Me.UpdateCallInMessage either way.
    public mutating func callEdited(_ text: String) -> [OperatingAction] {
        if text.isEmpty { nrSent = false }
        pendingCallEdits += 1
        return [.updateCallInMessage(text)]
    }

    /// UpdateCallInMessage's answer: False clears CallSent, unless a
    /// msgHisCall went out after the edit was made.
    public mutating func callEditResult(applied: Bool) {
        if pendingCallEdits > 0 { pendingCallEdits -= 1 }
        if staleCallEdits > 0 {
            staleCallEdits -= 1
            return
        }
        if !applied { callSent = false }
    }

    /// Esc: abort the send; Me.Msg's flags come back via abortResult.
    public func escape() -> [OperatingAction] { [.abortSend] }

    /// FormKeyPress #27: msgHisCall / msgNR in Tst.Me.Msg clear the flags.
    public mutating func abortResult(hadHisCall: Bool, hadNr: Bool) {
        if hadHisCall { callSent = false }
        if hadNr { nrSent = false }
    }

    /// Edit1Enter / Edit2Enter, on every focus change into a box.
    public func focusEntered(_ field: EntryField, _ s: EntrySnapshot) -> [OperatingAction] {
        switch field {
        case .call: return Self.edit1Enter(s.call)
        case .rst: return s.rst.count == 3 ? [.selectInRst(location: 1, length: 1)] : []
        case .nr, .other: return []
        }
    }

    /// Edit1Enter: P := Pos('?', Text); if P > 1, select it.
    static func edit1Enter(_ call: String) -> [OperatingAction] {
        guard let i = call.utf16.firstIndex(of: UInt16(UInt8(ascii: "?"))) else { return [] }
        let p = call.utf16.distance(from: call.utf16.startIndex, to: i)
        return p > 0 ? [.selectInCall(location: p, length: 1)] : []
    }
}
