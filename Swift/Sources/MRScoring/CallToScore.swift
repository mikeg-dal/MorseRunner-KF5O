// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Log.pas:79 (CallToScore) port. Returns the Morse-time cost
// of sending `call` in units of one dot-length:
//
//     '.' → 2   (one dot key-down + one space)
//     '-' → 4   (three-dot key-down + one space)
//     ' ' → 2   (inter-character gap)
//
// Pascal starts the accumulator at -1 (the encoded string ends with a
// trailing space whose cost we don't count). We mirror that exactly.
//
// HST scoring is the sum of this value across logged QSOs; longer /
// dash-heavier calls earn more points. WPX scoring does not use this
// — see ExtractPrefix.swift for the WPX multiplier.

import MRCore
import MRDSP

/// Pascal CallToScore: HST points for `call` (see the file comment).
/// Non-ASCII bytes have no Morse code and are skipped, as in the C++.
public func callToScore(_ call: String) -> Int {
    // Pascal: S := Keyer.Encode(S); Result := -1; for each char {
    //   '.': Inc(Result, 2);  '-': Inc(Result, 4);  ' ': Inc(Result, 2);
    // }
    // The encoded stream uses '.', '-', ' ' (inter-character gap) and
    // '~' (end-of-message marker). Pascal ignores '~' implicitly by
    // never matching it in the case statement; we do the same.
    var score = -ScoringK.hstStartPenalty
    for b in MorseTable.encode(call).utf8 {
        switch b {
        case UInt8(ascii: "."): score += ScoringK.hstDotCost
        case UInt8(ascii: "-"): score += ScoringK.hstDashCost
        case UInt8(ascii: " "): score += ScoringK.hstSpaceCost
        default: break  // '~' or unexpected — ignore
        }
    }
    return score
}
