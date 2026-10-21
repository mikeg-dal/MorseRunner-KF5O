// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Morse code table and text encoder. Port of src/dsp/MorseTable.cpp
// (VCL/MorseTbl.pas + MorseKey.pas Encode).
//
// Encoded form: '.' dot, '-' dash, ' ' gap, '~' end-of-message marker
// (replaces the final gap so the keyer emits a one-unit tail).
//
// Case folding is the C++ std::toupper (C locale): ASCII letters only.

import MRCore

public enum MorseTable {
    /// The 48 MorseTbl.pas entries. Single-character keys are reachable
    /// through `pattern(for:)`; the 2-letter prosign mnemonics through
    /// `prosign(_:)`.
    static let entries: [(key: String, pattern: String)] = [
        ("1", ".----"), ("2", "..---"), ("3", "...--"), ("4", "....-"),
        ("5", "....."), ("6", "-...."), ("7", "--..."), ("8", "---.."),
        ("9", "----."), ("0", "-----"),
        ("A", ".-"), ("B", "-..."), ("C", "-.-."), ("D", "-.."),
        ("E", "."), ("F", "..-."), ("G", "--."), ("H", "...."),
        ("I", ".."), ("J", ".---"), ("K", "-.-"), ("L", ".-.."),
        ("M", "--"), ("N", "-."), ("O", "---"), ("P", ".--."),
        ("Q", "--.-"), ("R", ".-."), ("S", "..."), ("T", "-"),
        ("U", "..-"), ("V", "...-"), ("W", ".--"), ("X", "-..-"),
        ("Y", "-.--"), ("Z", "--.."),
        ("/", "-..-."), (".", ".-.-.-"), (",", "--..--"),
        ("?", "..--.."), ("=", "-...-"),
        ("\\", "...-."),
        ("sk", "...-.-"), ("ar", ".-.-."), ("kn", "-.--."),
        ("cq", "-.-.--.-"), ("bk", "-...-.-"), ("dx", "-..-..-"),
    ]

    /// ASCII byte → pattern, for single-character keys.
    private static let byChar: [UInt8: [UInt8]] = {
        var m: [UInt8: [UInt8]] = [:]
        for e in entries where e.key.utf8.count == 1 {
            m[e.key.utf8.first!] = Array(e.pattern.utf8)
        }
        return m
    }()

    private static let byProsign: [String: String] = {
        var m: [String: String] = [:]
        for e in entries where e.key.utf8.count > 1 {
            m[ByteString.asciiUppercased(e.key)] = e.pattern
        }
        return m
    }()

    /// Pattern for one character (case-insensitive, like the C++), or
    /// empty when the character has no Morse code.
    public static func pattern(for c: Character) -> String {
        guard let b = c.asciiValue, let p = byChar[ByteString.asciiUppercased(b)] else { return "" }
        return String(decoding: p, as: UTF8.self)
    }

    public static func prosign(_ mnemonic: String) -> String {
        byProsign[ByteString.asciiUppercased(mnemonic)] ?? ""
    }

    /// MorseKey.pas Encode: per-character lookup, ' ' and '_' become one
    /// gap, unknown characters are dropped, each code is followed by a
    /// gap, and the final gap becomes '~'.
    public static func encode(_ text: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count * 6)
        for b in text.utf8 {
            if b == 32 || b == 95 {  // ' ' or '_'
                out.append(32)
                continue
            }
            guard let p = byChar[ByteString.asciiUppercased(b)] else { continue }
            out.append(contentsOf: p)
            out.append(32)
        }
        if !out.isEmpty {
            out[out.count - 1] = 126  // '~'
        }
        return String(decoding: out, as: UTF8.self)
    }
}

/// Free-function spelling of the C++ mr::dsp::encodeMessage.
public func encodeMessage(_ text: String) -> String {
    MorseTable.encode(text)
}
