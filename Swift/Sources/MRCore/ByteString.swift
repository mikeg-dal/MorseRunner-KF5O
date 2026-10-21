// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Byte-level string helpers. The C++ engine works on std::string, i.e.
// on raw bytes with C-locale (ASCII-only) case mapping; Swift's String
// operations are Unicode-aware and would differ on non-ASCII input. These
// helpers reproduce the std::string semantics once, for every module.

public enum ByteString {
    /// `std::toupper` in the C locale: a–z → A–Z, every other byte
    /// (including all non-ASCII bytes) unchanged.
    @inlinable
    public static func asciiUppercased(_ b: UInt8) -> UInt8 {
        (b >= 97 && b <= 122) ? b - 32 : b
    }

    /// ASCII upper-casing of every byte of `s` (Pascal UpperCase /
    /// C `toupper` per char). Non-ASCII text passes through unchanged.
    public static func asciiUppercased(_ s: String) -> String {
        String(decoding: s.utf8.map(asciiUppercased), as: UTF8.self)
    }

    /// Index of the first occurrence of `needle` in `s` at or after
    /// `start` (`std::string::find`). nil for an empty needle.
    public static func firstIndex(of needle: [UInt8], in s: [UInt8], from start: Int = 0) -> Int? {
        if needle.isEmpty || start < 0 || s.count - start < needle.count {
            return nil
        }
        for i in start...(s.count - needle.count) where s[i..<(i + needle.count)].elementsEqual(needle) {
            return i
        }
        return nil
    }

    /// Pascal StringReplace(s, from, to, [rfReplaceAll]) / the C++
    /// find-replace loop: left to right, non-overlapping, scanning
    /// resumes after the replaced text (inserted bytes are never
    /// rescanned). An empty `from` returns `s` unchanged.
    public static func replacingAll(_ from: [UInt8], with to: [UInt8], in s: [UInt8]) -> [UInt8] {
        if from.isEmpty || s.count < from.count {
            return s
        }
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if i + from.count <= s.count && s[i..<(i + from.count)].elementsEqual(from) {
                out.append(contentsOf: to)
                i += from.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out
    }

    /// Pascal StringReplace(s, from, to, []) — the FIRST occurrence only
    /// (C++ `s.replace(s.find(from), from.size(), to)`). An empty `from`
    /// returns `s` unchanged.
    public static func replacingFirst(_ from: [UInt8], with to: [UInt8], in s: [UInt8]) -> [UInt8] {
        guard let p = firstIndex(of: from, in: s) else { return s }
        var out = s
        out.replaceSubrange(p..<(p + from.count), with: to)
        return out
    }
}
