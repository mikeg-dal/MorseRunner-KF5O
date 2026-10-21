// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// What a VCL TEdit does to typing: CharCase = ecUpperCase, the form's
// OnKeyPress allow-list (Edit1KeyPress etc.) and MaxLength. Applied to
// the inserted text only: a keystroke that would exceed MaxLength is
// refused (the Windows edit control's EM_LIMITTEXT), and a paste is cut
// to the room left.

import Foundation

public struct EntryFilter: Sendable, Equatable {
    /// Characters accepted after upper-casing and translation; nil
    /// accepts anything (Edit4 has no OnKeyPress filter).
    public var allowed: Set<Character>?
    /// VCL MaxLength; 0 = unlimited.
    public var maxLength: Int
    public var uppercase: Bool
    /// Letters replaced as they are typed, after upper-casing and before
    /// the allow-list (the cut-number deviation in RST / NR).
    public var translate: [Character: Character]

    public init(allowed: String?, maxLength: Int, uppercase: Bool,
                translate: [Character: Character] = [:]) {
        self.allowed = allowed.map(Set.init)
        self.maxLength = maxLength
        self.uppercase = uppercase
        self.translate = translate
    }

    // MARK: Main.dfm / Main.pas configurations

    /// Edit1: ecUpperCase, MaxLength 12, Edit1KeyPress [A-Za-z0-9/?].
    public static let call = EntryFilter(allowed: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?",
                                         maxLength: 12, uppercase: true)
    /// Cut numbers as heard (deliberate deviation, parity-checklist):
    /// T and O are 0, N is 9 — the letters NumberFormat sends.
    public static let cutNumbers: [Character: Character] = ["T": "0", "O": "0", "N": "9"]
    /// Edit2: MaxLength 3, Edit2KeyPress [0-9] (+ cut numbers).
    public static let rst = EntryFilter(allowed: "0123456789", maxLength: 3, uppercase: true,
                                        translate: cutNumbers)
    /// Edit3: MaxLength 4, Edit3KeyPress [0-9] (+ cut numbers).
    public static let nr = EntryFilter(allowed: "0123456789", maxLength: 4, uppercase: true,
                                       translate: cutNumbers)
    /// Edit4 (My Call): ecUpperCase only. Main.dfm sets no MaxLength and
    /// there is no OnKeyPress filter.
    public static let myCall = EntryFilter(allowed: nil, maxLength: 0, uppercase: true)

    /// TSpinEdit's numeric field.
    public static func digits(maxLength: Int) -> EntryFilter {
        EntryFilter(allowed: "0123456789", maxLength: maxLength, uppercase: false)
    }

    // MARK: Filtering

    /// Upper-case → translate → allow-list, character by character.
    public func clean(_ s: String) -> String {
        var out = ""
        for ch in s {
            var c = ch
            if uppercase {
                // ecUpperCase converts one character to one character.
                let up = String(c).uppercased()
                if up.count == 1, let u = up.first { c = u }
            }
            if let t = translate[c] { c = t }
            if let allowed, !allowed.contains(c) { continue }
            out.append(c)
        }
        return out
    }

    public enum Outcome: Equatable, Sendable {
        /// The proposed text is fine as it is.
        case accept
        /// Use `text` instead, with the caret at UTF-16 offset `caret`.
        case replace(text: String, caret: Int)
        /// Refuse the edit; the field keeps its original text.
        case reject
    }

    /// Decides an edit of `original` (whose selection, in UTF-16 units,
    /// was `selection`) that produced `proposed`.
    public func filter(original: String, selection: NSRange, proposed: String) -> Outcome {
        let (prefix, inserted, suffix) = Self.split(original: original, selection: selection,
                                                    proposed: proposed)
        let cleaned = clean(inserted)
        var kept = Array(cleaned)
        if maxLength > 0 {
            let room = maxLength - (prefix.count + suffix.count)
            if !kept.isEmpty, room <= 0 { return .reject }
            if kept.count > room { kept = Array(kept.prefix(max(0, room))) }
        }
        let insertion = String(kept)
        if insertion == inserted { return .accept }
        // Every typed character was refused (KeyPress Key := #0): nothing
        // happens, not even the deletion of a selection.
        if insertion.isEmpty { return .reject }
        let text = prefix + insertion + suffix
        return .replace(text: text, caret: (prefix + insertion).utf16.count)
    }

    /// Splits `proposed` into the unchanged head, the inserted text and
    /// the unchanged tail. Uses the original selection when the edit
    /// replaced exactly it (typing, paste); otherwise the longest common
    /// prefix and suffix (backspace / delete with no selection).
    static func split(original: String, selection: NSRange,
                      proposed: String) -> (String, String, String) {
        let o16 = Array(original.utf16), p16 = Array(proposed.utf16)
        let loc = min(max(0, selection.location), o16.count)
        let end = min(o16.count, loc + max(0, selection.length))
        let head = o16[..<loc], tail = o16[end...]
        if p16.count >= head.count + tail.count,
           p16.starts(with: head), p16.reversed().starts(with: tail.reversed()),
           let h = decodeUTF16(head),
           let m = decodeUTF16(p16[head.count..<(p16.count - tail.count)]),
           let t = decodeUTF16(tail) {
            return (h, m, t)
        }
        let a = Array(original), b = Array(proposed)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        return (String(b[..<p]), String(b[p..<(b.count - s)]), String(b[(b.count - s)...]))
    }
}

private func decodeUTF16(_ units: ArraySlice<UInt16>) -> String? {
    var it = units.makeIterator()
    var out = ""
    var decoder = UTF16()
    while true {
        switch decoder.decode(&it) {
        case .scalarValue(let v): out.unicodeScalars.append(v)
        case .emptyInput: return out
        case .error: return nil
        }
    }
}
