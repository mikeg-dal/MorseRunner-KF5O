// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include <cmath>

namespace mr::core {

// Delphi's System.Round rounds exact halves to the nearest even integer
// (banker's rounding); std::lround rounds them away from zero. The two
// differ on exact ties such as Round(11025 / 450) = Round(24.5) = 24, which
// sets the modulator carrier, or Round(13230 / 12) = 1102 samples per unit.
// std::nearbyint uses the current rounding mode, which is round-to-nearest-
// even unless something calls fesetround (nothing in this program does).
[[nodiscard]] inline int delphiRound(double x) noexcept {
    return static_cast<int>(std::nearbyint(x));
}

}  // namespace mr::core
