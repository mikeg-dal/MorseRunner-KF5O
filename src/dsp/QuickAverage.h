// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/QuickAvg.pas (TQuickAverage). One-sample-at-a-time
// recursive multi-pass moving average. Different from MovingAverage in
// that the delay line is circular and the bookkeeping is per-sample
// instead of per-block — used by Qsb where new gain samples are
// generated one at a time to drive Rayleigh fading.

#pragma once

#include <vector>

namespace mr::dsp {

class QuickAverage {
public:
    QuickAverage();

    void setPoints(int points);
    void setPasses(int passes);

    [[nodiscard]] int points() const noexcept { return points_; }
    [[nodiscard]] int passes() const noexcept { return passes_; }

    void reset();

    // Real-valued one-shot filter call. Returns the filtered output for
    // the just-pushed sample.
    float filter(float v);

    // Complex-valued one-shot filter call. Pascal exposes this as the
    // primary form because Qsb computes a 2-D Gaussian step before
    // taking its magnitude.
    void filterComplex(float re, float im, float& outRe, float& outIm);

    // Magnitude of the filtered (re, im) pair — convenience wrapper.
    [[nodiscard]] float filteredModule(float re, float im);

private:
    float doFilter(float v, std::vector<std::vector<double>>& bufs);

    int points_ = 128;
    int passes_ = 4;
    int idx_ = 0;
    int prevIdx_ = 127;
    float scale_ = 1.0F;
    // Bufs are doubles in the original — accumulated state needs the
    // extra headroom because the cumulative sums can grow unbounded.
    std::vector<std::vector<double>> reBufs_;
    std::vector<std::vector<double>> imBufs_;
};

}  // namespace mr::dsp
