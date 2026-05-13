// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include <cstddef>
#include <vector>

namespace mr::dsp {

// Plain struct mirroring the Pascal `TReImArrays` record. Real and
// imaginary parts share equal length. Pre-allocated by the simulation
// engine to the maximum buffer size and reused; the hot path never grows
// it, so no allocations happen during audio rendering.
struct ComplexBuf {
    std::vector<float> re;
    std::vector<float> im;

    void resize(std::size_t n) {
        re.resize(n);
        im.resize(n);
    }

    [[nodiscard]] std::size_t size() const noexcept { return re.size(); }

    void clear() noexcept {
        std::fill(re.begin(), re.end(), 0.0F);
        std::fill(im.begin(), im.end(), 0.0F);
    }
};

}  // namespace mr::dsp
