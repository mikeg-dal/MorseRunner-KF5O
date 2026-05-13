// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/MorseTbl.pas. The original stores entries as the string
// "X[.-...]freq" — character, bracketed dot/dash pattern, English-letter
// frequency hint used only by the random-text generator (unused by the
// keyer itself). We split it into a plain character-to-pattern map.
//
// Encoding alphabet for the rendered pattern:
//     '.'  one dot unit + one space unit
//     '-'  three dot units + one space unit
//     ' '  inter-character gap (two extra space units)
//     '~'  end-of-message marker (one space unit)

#pragma once

#include <string>
#include <string_view>

namespace mr::dsp {

// Returns the Morse pattern for `c`. Case-insensitive for ASCII letters.
// Multi-character prosigns (SK, AR, KN, CQ, BK, DX) are reachable by the
// dedicated lookup `prosignFor()`. Returns empty string_view when the
// character has no pattern (the keyer turns this into a space).
[[nodiscard]] std::string_view patternForChar(char c) noexcept;

// Returns the Morse pattern for a two-character prosign mnemonic such as
// "SK" or "AR". Lowercase or uppercase accepted. Empty on miss.
[[nodiscard]] std::string_view patternForProsign(std::string_view mnemonic) noexcept;

// Encodes a free-form message into the keyer's internal alphabet
// ('.', '-', ' ', '~'). The original Delphi `TKeyer.Encode` operates
// character-by-character; this port preserves that behavior.
[[nodiscard]] std::string encodeMessage(std::string_view text);

}  // namespace mr::dsp
