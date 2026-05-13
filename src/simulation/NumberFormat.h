// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas::NrAsText. Renders the "RST + NR" string the
// station will key, applying the standard CW cut-number substitutions
// and (for LID stations with the corruption flag set) an injected
// error followed by an "EEEEE <correct nr>" correction.
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
//
// The original passes RunMode = rmHst as a flag; we accept it as a
// boolean here because the simulation namespace doesn't depend on the
// Ini layer.

#pragma once

#include <string>

namespace mr::core { class Random; }

namespace mr::sim {

struct NrFormatOptions {
    int rst = 599;
    int nr = 1;
    bool hstMode = false;
    bool lidError = false;  // inject an error and trailing "EEEEE <nr>"
};

// Returns the keyed CW text for the given RST/NR pair.
// Pascal: Station.pas::NrAsText.
[[nodiscard]] std::string nrAsText(const NrFormatOptions& opts,
                                   mr::core::Random& rng);

}  // namespace mr::sim
