// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas::NrAsText (C++ src/simulation/NumberFormat). Renders
// the "RST + NR" string the station will key, applying the standard CW
// cut-number substitutions and (for LID stations with the corruption
// flag set) an injected error followed by an "EEEEE <correct nr>"
// correction.
//
// Substitution rules — applied in this order, all probabilities drawn
// fresh on each call:
//
//   1. "599"  → "5NN"               (always; ham-radio convention)
//   2. "000"  → "TTT"               (HST mode only suppressed)
//   3. "00"   → "TT"                (HST mode only suppressed)
//   4. "0"    → "O"  p=0.40         (HST mode only suppressed)
//      else   → "T"  p=0.97         (3% retained as literal "0")
//   5. "9"    → "N"  p=0.97         (3% retained as literal "9")
//   6. LID    → corrupt rightmost digit in 2..7 then append " EEEEE <nr>"

import Foundation
import MRCore

public struct NrFormatOptions: Sendable {
    public var rst = 599
    public var nr = 1
    public var hstMode = false
    /// Inject an error and trailing "EEEEE <nr>".
    public var lidError = false

    public init(rst: Int = 599, nr: Int = 1, hstMode: Bool = false, lidError: Bool = false) {
        self.rst = rst
        self.nr = nr
        self.hstMode = hstMode
        self.lidError = lidError
    }
}

/// Returns the keyed CW text for the given RST/NR pair.
/// Pascal: Station.pas::NrAsText.
public func nrAsText(_ opts: NrFormatOptions, _ rng: Random) -> String {
    // Pascal: Format('%d%.3d', [RST, NR]). RST is 3 digits, NR is
    // padded to at least 3 digits.
    // `%ld` on the 64-bit Int: identical text for every value a C++ int
    // can hold, and no Int32 conversion trap for larger ones.
    var out = String(format: "%ld%.3ld", opts.rst, opts.nr).bytes

    // LID error injection: pick the rightmost digit in [2..7], bump it
    // up or down by 1, then append "EEEEE <correct nr>" so the receiver
    // hears the typo + correction. Done BEFORE the cut-number
    // substitutions so the substitutions apply to the corrupted form
    // too (matching Pascal Station.pas::NrAsText control flow).
    if opts.lidError {
        // Pascal: `Idx := Length(Result); if not (Result[Idx] in ['2'..'7']) then Dec(Idx)`.
        // Try last digit first; fall back to next-to-last.
        let two = UInt8(ascii: "2")
        let seven = UInt8(ascii: "7")
        var idx = out.count
        if idx > 0 && (out[idx - 1] < two || out[idx - 1] > seven) {
            idx -= 1
        }
        if idx > 0 && out[idx - 1] >= two && out[idx - 1] <= seven {
            let target = idx - 1
            if rng.uniform01() < 0.5 {
                out[target] -= 1
            } else {
                out[target] += 1
            }
            // Append correction tail with correct NR. Note: the C++ spec
            // appends it directly, with no space before "EEEEE".
            out += String(format: "EEEEE %.3ld", opts.nr).bytes
        }
    }

    // RST 599 → 5NN. In CW the "9"s in RST are usually sent as the
    // abbreviated "N" because it's faster to key.
    out = ByteString.replacingAll("599".bytes, with: "5NN".bytes, in: out)

    if !opts.hstMode {
        // Triple/double-zero collapses to TTT/TT first (otherwise the
        // per-digit '0' substitution below would chew them up wrong).
        out = ByteString.replacingAll("000".bytes, with: "TTT".bytes, in: out)
        out = ByteString.replacingAll("00".bytes, with: "TT".bytes, in: out)

        // Pascal: `if Random < 0.4 then '0' -> 'O' else if Random < 0.97
        // then '0' -> 'T'`. StringReplace with rfReplaceAll applies the
        // SAME substitution to every occurrence after a single draw.
        if rng.uniform01() < SimK.cutZeroAsOProb {
            out = ByteString.replacingAll("0".bytes, with: "O".bytes, in: out)
        } else if rng.uniform01() < SimK.cutZeroAsTProb {
            out = ByteString.replacingAll("0".bytes, with: "T".bytes, in: out)
        }

        if rng.uniform01() < SimK.cutNineAsNProb {
            out = ByteString.replacingAll("9".bytes, with: "N".bytes, in: out)
        }
    }

    return out.asString
}
