// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal VCL/Crc32.pas port. Standard 256-entry table-driven CRC32.
// Pascal seeds with `$C90C2086` (ScoringK.crc32Seed) and the function
// returns the post-mix value as an 8-hex-digit string at the end of the
// WPX score submission line.

import MRCore

// Standard polynomial 0xEDB88320 CRC32 table. Identical to the array
// in Pascal VCL/Crc32.pas (built here rather than spelled out; the
// golden test pins every byte of output against the C++ literal table).
private let crcTable: [UInt32] = (0..<256).map { (n: Int) -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 {
        c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
    }
    return c
}

/// Pascal CalculateCRC32 over raw bytes: result := seed; for each byte,
/// result := (result shr 8) xor table[byte xor (result and $FF)].
/// No pre/post inversion.
public func calculateCrc32<S: Sequence>(bytes: S, seed: UInt32) -> UInt32
    where S.Element == UInt8 {
    var result = seed
    for b in bytes {
        result = (result >> 8) ^ crcTable[Int(b ^ UInt8(truncatingIfNeeded: result))]
    }
    return result
}

/// CRC32 of the string's UTF-8 bytes (the C++ hashes the std::string from
/// QString::toStdString(), which is UTF-8).
public func calculateCrc32(_ str: String, seed: UInt32) -> UInt32 {
    calculateCrc32(bytes: str.utf8, seed: seed)
}

/// PopupScoreWpx stamp: `inner + "[XXXXXXXX]"`, the CRC32 (seed
/// $C90C2086) of `inner` as 8 upper-case hex digits.
public func stampScoreLine(_ inner: String) -> String {
    let crc = calculateCrc32(inner, seed: ScoringK.crc32Seed)
    let hex = String(crc, radix: 16, uppercase: true)
    return inner + "[" + String(repeating: "0", count: 8 - hex.count) + hex + "]"
}
