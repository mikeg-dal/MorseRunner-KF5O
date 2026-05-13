// Morse Runner — macOS Qt 6 port
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
// — see scoring/ExtractPrefix.h for the WPX multiplier.

#pragma once

#include <string_view>

namespace mr::scoring {

[[nodiscard]] int callToScore(std::string_view call);

}  // namespace mr::scoring
