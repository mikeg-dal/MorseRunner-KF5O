// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/QuickAverage.h"

#include <algorithm>
#include <cmath>

namespace mr::dsp {

QuickAverage::QuickAverage() {
    reset();
}

void QuickAverage::setPoints(int points) {
    points_ = std::max(1, points);
    reset();
}

void QuickAverage::setPasses(int passes) {
    // Pascal: clamps to [1, 8]; the recursion's numerical stability
    // degrades past 8 passes (the cumulative sums underflow scale).
    passes_ = std::clamp(passes, 1, 8);
    reset();
}

void QuickAverage::reset() {
    reBufs_.assign(static_cast<std::size_t>(passes_ + 1),
                   std::vector<double>(static_cast<std::size_t>(points_), 0.0));
    imBufs_.assign(static_cast<std::size_t>(passes_ + 1),
                   std::vector<double>(static_cast<std::size_t>(points_), 0.0));
    scale_ = static_cast<float>(std::pow(static_cast<double>(points_), -passes_));
    idx_ = 0;
    prevIdx_ = points_ - 1;
}

float QuickAverage::doFilter(float v, std::vector<std::vector<double>>& bufs) {
    double result = v;
    for (int p = 1; p <= passes_; ++p) {
        const double prev = bufs[static_cast<std::size_t>(p)][static_cast<std::size_t>(prevIdx_)];
        const double curr =
            bufs[static_cast<std::size_t>(p - 1)][static_cast<std::size_t>(idx_)];
        bufs[static_cast<std::size_t>(p - 1)][static_cast<std::size_t>(idx_)] = result;
        result = prev - curr + result;
    }
    bufs[static_cast<std::size_t>(passes_)][static_cast<std::size_t>(idx_)] = result;
    return static_cast<float>(result) * scale_;
}

float QuickAverage::filter(float v) {
    const float out = doFilter(v, reBufs_);
    prevIdx_ = idx_;
    idx_ = (idx_ + 1) % points_;
    return out;
}

void QuickAverage::filterComplex(float re, float im, float& outRe, float& outIm) {
    outRe = doFilter(re, reBufs_);
    outIm = doFilter(im, imBufs_);
    prevIdx_ = idx_;
    idx_ = (idx_ + 1) % points_;
}

float QuickAverage::filteredModule(float re, float im) {
    float r = 0.0F;
    float i = 0.0F;
    filterComplex(re, im, r, i);
    return std::sqrt(r * r + i * i);
}

}  // namespace mr::dsp
