// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// ByteString: std::string-style byte operations (C-locale toupper,
// find, Pascal StringReplace).

import MRCore
import Testing

private func b(_ s: String) -> [UInt8] { Array(s.utf8) }

@Suite struct ByteStringTests {
    @Test func uppercasesAsciiLettersOnly() {
        #expect(ByteString.asciiUppercased("k1abc/p?") == "K1ABC/P?")
        #expect(ByteString.asciiUppercased("") == "")
        // Non-ASCII is untouched (Swift's uppercased() would give "SS"/"É").
        #expect(ByteString.asciiUppercased("straße é") == "STRAßE é")
        #expect(ByteString.asciiUppercased("@[`{") == "@[`{")  // neighbours of A-Z / a-z
    }

    @Test func uppercasesEveryByteValueLikeToupper() {
        for v in 0...255 {
            let c = UInt8(v)
            let want: UInt8 = (97...122).contains(v) ? c - 32 : c
            #expect(ByteString.asciiUppercased(c) == want)
        }
    }

    @Test func firstIndex() {
        #expect(ByteString.firstIndex(of: b("/P"), in: b("W1AW/P/P")) == 4)
        #expect(ByteString.firstIndex(of: b("/P"), in: b("W1AW/P/P"), from: 5) == 6)
        #expect(ByteString.firstIndex(of: b("/P"), in: b("W1AW/P/P"), from: 7) == nil)
        #expect(ByteString.firstIndex(of: b("/P"), in: b("W1AW/P/P"), from: 99) == nil)
        #expect(ByteString.firstIndex(of: b("/P"), in: b("W1AW/P/P"), from: -1) == nil)
        #expect(ByteString.firstIndex(of: b("ABC"), in: b("AB")) == nil)
        #expect(ByteString.firstIndex(of: [], in: b("AB")) == nil)
        #expect(ByteString.firstIndex(of: b("AB"), in: b("AB")) == 0)
    }

    @Test(arguments: [
        ("//", "/", "///", "//"),          // non-overlapping, left to right
        ("//", "/", "////", "//"),
        ("aa", "b", "aaaaa", "bba"),
        ("a", "aa", "aba", "aabaa"),       // inserted text is not rescanned
        ("x", "", "xAxBx", "AB"),
        ("", "Z", "ABC", "ABC"),           // empty pattern: unchanged
        ("ABCD", "Z", "ABC", "ABC"),       // pattern longer than input
        ("<my>", "VE3NEA", "<my> <my>", "VE3NEA VE3NEA"),
    ])
    func replacingAll(_ from: String, _ to: String, _ s: String, _ want: String) {
        #expect(ByteString.replacingAll(b(from), with: b(to), in: b(s)) == b(want))
    }

    @Test(arguments: [
        ("/P|", "", "W1AW/P|", "W1AW"),
        ("/M|", "", "W1AW/MM|", "W1AW/MM|"),
        ("|", "", "A||", "A|"),            // first occurrence only
        ("Q", "", "ABC", "ABC"),
        ("", "Z", "ABC", "ABC"),
    ])
    func replacingFirst(_ from: String, _ to: String, _ s: String, _ want: String) {
        #expect(ByteString.replacingFirst(b(from), with: b(to), in: b(s)) == b(want))
    }

    @Test func operatesOnBytesNotCharacters() {
        // "é" as U+00E9 vs "e" + U+0301 are equal Strings but different
        // bytes; byte search must tell them apart, like std::string::find.
        let composed = b("caf\u{E9}")
        let decomposed = b("cafe\u{301}")
        #expect(ByteString.firstIndex(of: b("\u{E9}"), in: composed) == 3)
        #expect(ByteString.firstIndex(of: b("\u{E9}"), in: decomposed) == nil)
        #expect(ByteString.replacingAll(b("e"), with: b("E"), in: decomposed) == b("cafE\u{301}"))
    }
}
