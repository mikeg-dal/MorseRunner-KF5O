// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// KeyPreview: TMainForm.FormKeyDown and FormKeyPress as one mapping from
// a key event to a command.
//
// Modifier rule (one rule, everywhere): Pascal "Ctrl" is Control OR
// Command — macOS reserves several Control combinations (Control-Up is
// Mission Control), so Command stands in. Alt is Option. Command combos
// that Pascal does not define (Cmd-Q, Cmd-C, ...) are left to the menus.
//
// Keys are matched on the character the key produces, never on its
// hardware key code, so Alt-W / Ctrl-W work on any layout (AZERTY's W is
// on a different key).

import Foundation

/// The NSEvent function-key code points (NSEvent.h; AppKit-free here).
public enum FunctionKey {
    public static let upArrow: UInt32 = 0xF700
    public static let downArrow: UInt32 = 0xF701
    public static let f1: UInt32 = 0xF704
    public static let f8: UInt32 = 0xF70B
    public static let f9: UInt32 = 0xF70C
    public static let f10: UInt32 = 0xF70D
    public static let f11: UInt32 = 0xF70E
    public static let insert: UInt32 = 0xF727
    public static let pageUp: UInt32 = 0xF72C
    public static let pageDown: UInt32 = 0xF72D
    public static let help: UInt32 = 0xF746

    /// F1…F12 → code point.
    public static func f(_ n: Int) -> UInt32 { f1 + UInt32(n - 1) }
}

public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Pascal ssCtrl.
    public var ctrl: Bool { contains(.control) || contains(.command) }
    /// Pascal ssAlt.
    public var alt: Bool { contains(.option) }
}

public enum KeyCommand: Sendable, Equatable {
    /// Insert, ';': <his> <#>.
    case hisCallAndNr
    /// Return / keypad Enter: ProcessEnter; Ctrl/Shift/Alt force a save.
    case enter(forceSave: Bool)
    /// F11, Alt-W, Ctrl-W.
    case wipe
    /// Up / Down: IncRit(±1).
    case rit(Int)
    /// Ctrl-Up / Ctrl-Down: SetBw(ItemIndex ± 1), ignored in HST.
    case bandwidth(Int)
    /// PgUp, Alt/Ctrl-F10.
    case speedUp
    /// PgDn, Alt/Ctrl-F9.
    case speedDown
    /// Esc.
    case abort
    /// '.', '+', '[', ',': TU & save.
    case tuAndSave
    /// Space.
    case space
    /// '\': CQ.
    case cq
    /// Swallowed with no action (FormKeyDown's Key := 0 for a bare F9 /
    /// F10).
    case ignore

    /// - Parameters:
    ///   - key: the first scalar of charactersIgnoringModifiers.
    ///   - characters: what the key types with its modifiers (NSEvent
    ///     characters), for the FormKeyPress characters.
    /// - Returns: nil when the event is not the form's (it goes on to the
    ///   menus and the focused control).
    public static func map(key: UInt32, characters: String, modifiers: KeyModifiers) -> KeyCommand? {
        let ctrl = modifiers.ctrl, alt = modifiers.alt, shift = modifiers.contains(.shift)

        // FormKeyDown.
        switch key {
        case FunctionKey.insert, FunctionKey.help:
            return .hisCallAndNr
        case 13, 3:
            return .enter(forceSave: ctrl || shift || alt)
        case FunctionKey.f11:
            return .wipe
        case FunctionKey.upArrow:
            return ctrl ? .bandwidth(1) : .rit(1)
        case FunctionKey.downArrow:
            return ctrl ? .bandwidth(-1) : .rit(-1)
        case FunctionKey.pageUp:
            return .speedUp
        case FunctionKey.pageDown:
            return .speedDown
        case FunctionKey.f9:
            return alt || ctrl ? .speedDown : .ignore
        case FunctionKey.f10:
            return alt || ctrl ? .speedUp : .ignore
        case 27:
            return .abort
        case UInt32(UInt8(ascii: "w")), UInt32(UInt8(ascii: "W")):
            // Alt-W (FormKeyDown) and ^W (FormKeyPress #23).
            if alt || ctrl { return .wipe }
        default:
            break
        }

        // Other Command / Control / Option combinations are not the form's.
        if ctrl || alt { return nil }

        // FormKeyPress.
        switch characters {
        case ";": return .hisCallAndNr
        case ".", "+", "[", ",": return .tuAndSave
        case " ": return .space
        case "\\": return .cq
        default: return nil
        }
    }
}
