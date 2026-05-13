// Morse Runner — macOS Qt 6 port
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
//   7. Truncate to 5 characters.
//
// Examples:
//   K1ABC       → K1
//   VE3NEA      → VE3
//   VE3NEA/QRP  → VE3
//   VE3NEA/P    → VE3
//   VE3NEA/W1   → W1
//   K/N1MM      → K0
//   P29SX       → P29

#pragma once

#include <string>
#include <string_view>

namespace mr::scoring {

[[nodiscard]] std::string extractPrefix(std::string_view call);

}  // namespace mr::scoring
