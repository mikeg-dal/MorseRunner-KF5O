// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "scoring/CallToScore.h"

#include "dsp/MorseTable.h"

namespace mr::scoring {

int callToScore(std::string_view call) {
    // Pascal: S := Keyer.Encode(S); Result := -1; for each char {
    //   '.': Inc(Result, 2);  '-': Inc(Result, 4);  ' ': Inc(Result, 2);
    // }
    // The encoded stream uses '.', '-', ' ' (inter-character gap) and
    // '~' (end-of-message marker). Pascal ignores '~' implicitly by
    // never matching it in the case statement; we do the same.
    const std::string encoded = mr::dsp::encodeMessage(call);
    int score = -1;
    for (const char c : encoded) {
        switch (c) {
            case '.': score += 2; break;
            case '-': score += 4; break;
            case ' ': score += 2; break;
            default:  break;  // '~' or unexpected — ignore
        }
    }
    return score;
}

}  // namespace mr::scoring
