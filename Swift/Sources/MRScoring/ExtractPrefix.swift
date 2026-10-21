// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Log.pas:157-203 (ExtractPrefix) port. Produces the WPX-style
// prefix used as the multiplier key in the score table.
//
// Algorithm summary (verbatim from Pascal):
//   1. Strip portable suffixes /QRP, /MM, /M, /P (in that order).
//   2. Collapse double slash // into a single /.
//   3. If the call still contains a /, split into S1/S2:
//      - If exactly one side is a single digit, the OTHER side becomes
//        the result and the digit is stashed as `Dig`.
//      - Otherwise shorter side wins (ties favor S1).
//      - If the chosen result still contains a /, the call is
//        invalid → return "".
//   4. Working right-to-left, drop trailing letters until either a
//      digit is found or only 3 chars remain.
//   5. If the last char isn't a digit, append '0'.
//   6. If `Dig` was stashed, replace the last char of the result
//      with it.
//   7. Truncate to 5 characters (bytes — see below).
//
// Examples:
//   K1ABC       → K1
//   VE3NEA      → VE3
//   VE3NEA/QRP  → VE3
//   VE3NEA/P    → VE3
//   VE3NEA/W1   → W1
//   K/N1MM      → K0
//   P29SX       → P29
//
// Works on bytes throughout, as the C++ works on std::string chars: the
// input is the call's UTF-8, lengths are byte counts and the 5-character
// cut is a 5-byte cut. `extractPrefix(bytes:)` returns exactly the C++
// bytes. `extractPrefix(_:)` decodes them as UTF-8; for non-ASCII input
// the cut can split a multibyte character, and a String cannot hold the
// resulting invalid sequence, so the split tail becomes U+FFFD. (Calls
// are ASCII in practice: the call field only accepts A-Z, 0-9, / and ?.)

import MRCore

private let slash = UInt8(ascii: "/")

@inline(__always)
private func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

// Pascal: StringReplace(Call, what, '', []) replaces the FIRST
// occurrence only — Pascal's portable-suffix stripping depends on order
// (the FIRST hit decides which suffix wins).
private func removeFirst(_ s: inout [UInt8], _ what: String) {
    s = ByteString.replacingFirst(Array(what.utf8), with: [], in: s)
}

/// WPX prefix of `callIn` as UTF-8 text (see the file comment for
/// non-ASCII input).
public func extractPrefix(_ callIn: String) -> String {
    String(decoding: extractPrefix(bytes: Array(callIn.utf8)), as: UTF8.self)
}

/// WPX prefix on raw bytes: byte-for-byte the C++ mr::scoring::extractPrefix.
public func extractPrefix(bytes callIn: [UInt8]) -> [UInt8] {
    // Pascal pre-strips modifiers by appending '|' as a sentinel so
    // the suffix patterns can match end-of-string explicitly.
    var call = callIn
    call.append(UInt8(ascii: "|"))
    removeFirst(&call, "/QRP|")
    removeFirst(&call, "/MM|")
    removeFirst(&call, "/M|")
    removeFirst(&call, "/P|")
    removeFirst(&call, "|")
    // Pascal: StringReplace(Call, '//', '/', [rfReplaceAll]).
    call = ByteString.replacingAll(Array("//".utf8), with: [slash], in: call)
    if call.count < 2 {
        return []
    }

    var dig: UInt8?          // Pascal: single-digit alternate
    var result: [UInt8]

    // Pascal indexes strings 1-based; `p = Pos('/', Call)` returns 0
    // when no slash is present. We work 0-based but keep the branches.
    if let p = call.firstIndex(of: slash) {
        if p == 0 {
            // Pascal: p == 1 (slash at start). Result = Copy(Call, 2, ..).
            result = Array(call[1...])
        } else if p == call.count - 1 {
            // Pascal: p == Length(Call) (slash at end).
            result = Array(call[..<p])
        } else {
            let s1 = Array(call[..<p])
            let s2 = Array(call[(p + 1)...])
            if s1.count == 1 && isDigit(s1[0]) {
                dig = s1[0]
                result = s2
            } else if s2.count == 1 && isDigit(s2[0]) {
                dig = s2[0]
                result = s1
            } else if s1.count <= s2.count {
                // Pascal: <= so ties favor S1.
                result = s1
            } else {
                result = s2
            }
        }
    } else {
        result = call
    }
    if result.contains(slash) {
        return []
    }

    // Pascal: for p := Length(Result) downto 3 do
    //           if Result[p] in DIGITS then Break
    //           else Delete(Result, p, 1);
    // Drops trailing non-digits while at least 3 chars remain, so at
    // least minPrefixLen (2) are always kept.
    while result.count > ScoringK.minPrefixLen {
        if isDigit(result[result.count - 1]) {
            break
        }
        result.removeLast()
    }

    if result.isEmpty {
        return []
    }

    // Pascal: if not (Result[Length(Result)] in DIGITS) then
    //           Result := Result + '0';
    if !isDigit(result[result.count - 1]) {
        result.append(UInt8(ascii: "0"))
    }
    // Pascal: if Dig <> '' then Result[Length(Result)] := Dig[1];
    if let d = dig {
        result[result.count - 1] = d
    }
    // Pascal: Result := Copy(Result, 1, 5);
    if result.count > ScoringK.maxPrefixLen {
        result.removeLast(result.count - ScoringK.maxPrefixLen)
    }
    return result
}
