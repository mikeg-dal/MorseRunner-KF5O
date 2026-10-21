// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
@testable import MRAppCore
import Testing

/// Applies a typed / pasted insertion the way NSTextField proposes it.
private func type(_ f: EntryFilter, into original: String, at loc: Int, replacing len: Int = 0,
                  _ inserted: String) -> (text: String, outcome: EntryFilter.Outcome) {
    let o = original as NSString
    let proposed = o.replacingCharacters(in: NSRange(location: loc, length: len), with: inserted)
    let outcome = f.filter(original: original, selection: NSRange(location: loc, length: len),
                           proposed: proposed)
    switch outcome {
    case .accept: return (proposed, outcome)
    case .replace(let t, _): return (t, outcome)
    case .reject: return (original, outcome)
    }
}

struct EntryFilterTests {
    @Test(arguments: [
        ("k", "K"), ("1", "1"), ("/", "/"), ("?", "?"), ("-", ""), (" ", ""), ("é", ""),
    ])
    func callKeyPress(_ typed: String, _ expected: String) {
        #expect(type(.call, into: "", at: 0, typed).text == expected)
    }

    @Test(arguments: [
        ("t", "0"), ("T", "0"), ("o", "0"), ("n", "9"), ("5", "5"), ("a", ""), ("e", ""),
    ])
    func cutNumbers(_ typed: String, _ expected: String) {
        #expect(type(.rst, into: "", at: 0, typed).text == expected)
        #expect(type(.nr, into: "", at: 0, typed).text == expected)
    }

    @Test func callFieldIsNotTranslated() {
        #expect(type(.call, into: "", at: 0, "t").text == "T")
        #expect(type(.call, into: "", at: 0, "o").text == "O")
    }

    @Test(arguments: [
        (EntryFilter.call, String(repeating: "A", count: 12)),
        (EntryFilter.rst, "599"),
        (EntryFilter.nr, "1234"),
    ])
    func maxLengthRejectsKeystroke(_ f: EntryFilter, _ full: String) {
        // VCL MaxLength refuses the character; it does not drop the tail.
        let r = type(f, into: full, at: 1, "7")
        #expect(r.outcome == .reject)
        #expect(r.text == full)
    }

    @Test func maxLengthAllowsReplacingASelection() {
        let r = type(.rst, into: "599", at: 1, replacing: 1, "7")
        #expect(r.outcome == .accept)
        #expect(r.text == "579")
    }

    @Test func pasteIsCutToTheRoomLeft() throws {
        let r = type(.nr, into: "1", at: 1, "23456")
        #expect(r.text == "1234")
        guard case .replace(_, let caret) = r.outcome else {
            Issue.record("expected replace")
            return
        }
        #expect(caret == 4)
    }

    @Test func caretFollowsTheFilteredInsertion() {
        // Typing lower case in the middle: the caret sits after it.
        let r = type(.call, into: "WAA", at: 1, "b")
        #expect(r.outcome == .replace(text: "WBAA", caret: 2))
        // Paste with refused characters: "x-1" → "X1" at 2.
        let p = type(.call, into: "AB", at: 2, "x-1")
        #expect(p.outcome == .replace(text: "ABX1", caret: 4))
    }

    @Test func refusedKeystrokeKeepsTheSelection() {
        // KeyPress Key := #0: nothing happens, the selection survives.
        let r = type(.nr, into: "123", at: 0, replacing: 3, "x")
        #expect(r.outcome == .reject)
        #expect(r.text == "123")
    }

    @Test func deletionsAreAlwaysAccepted() {
        #expect(EntryFilter.call.filter(original: "ABC", selection: NSRange(location: 3, length: 0),
                                        proposed: "AB") == .accept)
        #expect(EntryFilter.rst.filter(original: "599", selection: NSRange(location: 0, length: 3),
                                       proposed: "") == .accept)
    }

    @Test func myCallHasNoLengthLimit() {
        // Main.dfm Edit4 has no MaxLength.
        let long = String(repeating: "A", count: 30)
        #expect(type(.myCall, into: long, at: 30, "b").text == long + "B")
    }

    @Test func myCallUppercasesAnything() {
        #expect(type(.myCall, into: "", at: 0, "kf5o/p").text == "KF5O/P")
        #expect(type(.myCall, into: "", at: 0, " ").text == " ")  // Edit4 has no key filter
    }

    @Test func spinDigits() {
        let f = EntryFilter.digits(maxLength: 3)
        #expect(type(f, into: "12", at: 2, "a").outcome == .reject)
        #expect(type(f, into: "12", at: 2, "0").text == "120")
        #expect(type(f, into: "120", at: 3, "0").outcome == .reject)
        // Lower-case letters are not upper-cased in a spin edit.
        #expect(EntryFilter.digits(maxLength: 3).uppercase == false)
    }

    @Test func cleanOrder() {
        // upper-case → translate → allow-list.
        #expect(EntryFilter.rst.clean("tOn9x") == "0099")
        #expect(EntryFilter.call.clean("ab/c?d-") == "AB/C?D")
        #expect(EntryFilter(allowed: nil, maxLength: 0, uppercase: false).clean("aß") == "aß")
        // ß upper-cases to two letters; ecUpperCase keeps it one character.
        #expect(EntryFilter.myCall.clean("ß") == "ß")
    }

    @Test func splitPrefersTheSelection() {
        let (h, m, t) = EntryFilter.split(original: "AA", selection: NSRange(location: 1, length: 0),
                                          proposed: "AAA")
        #expect(h == "A" && m == "A" && t == "A")
        // Backspace (selection does not describe it): common prefix / suffix.
        let (h2, m2, t2) = EntryFilter.split(original: "ABC",
                                             selection: NSRange(location: 3, length: 0),
                                             proposed: "AC")
        #expect(h2 == "A" && m2 == "" && t2 == "C")
    }

    @Test func unlimitedLength() {
        let f = EntryFilter(allowed: nil, maxLength: 0, uppercase: false)
        let long = String(repeating: "x", count: 100)
        #expect(type(f, into: long, at: 100, "y").outcome == .accept)
    }
}
