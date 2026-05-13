// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/MovAvg.pas. Multi-pass cumulative-sum moving average. Each
// pass uses the recursion
//
//     y[i] = y[i-1] - x[i - Points] + x[i]
//
// which is O(1) per sample regardless of Points. P passes through it
// approximate a Gaussian closely enough that the audible response
// matches the original within the golden-WAV tolerance.
//
// State (delay line) is held in `passBuffers_` and persists across
// calls — necessary so successive blocks join without a click at the
// boundary. `reset()` zeroes the state; the PingPongFilter calls it on
// the *idle* filter every kFilterSwapBlocks blocks.

#pragma once

#include "dsp/ComplexBuf.h"

#include <cstddef>
#include <span>
#include <vector>

namespace mr::dsp {

class MovingAverage {
public:
    MovingAverage();

    // Configures the filter. Resets state. Pascal defaults: points=129,
    // passes=3, samplesInInput=512, gainDb=0. We use the same defaults
    // as a safety net; the Contest engine overrides them based on the
    // user's RX-bandwidth setting.
    void configure(int points, int passes, int samplesInInput, float gainDb);

    void setSamplesInInput(int samplesInInput);
    void setPoints(int points);
    void setPasses(int passes);
    void setGainDb(float gainDb);

    [[nodiscard]] int points() const noexcept { return points_; }
    [[nodiscard]] int passes() const noexcept { return passes_; }
    [[nodiscard]] int samplesInInput() const noexcept { return samplesInInput_; }
    [[nodiscard]] float gainDb() const noexcept { return gainDb_; }

    // Zeroes all delay lines. The recursive sum re-bootstraps from the
    // first call's input thereafter.
    void reset();

    // Filters `in` (length == samplesInInput) into `out` (same length).
    // In-place use (in == out) is supported.
    void process(std::span<const float> in, std::span<float> out);

    // Convenience: filter a ComplexBuf in place (uses a private second
    // delay chain for the Im channel so Re/Im don't cross-contaminate).
    void processComplex(ComplexBuf& buf);

private:
    void resetBuffer(std::vector<std::vector<float>>& bufChain) const;
    void doFilter(std::span<const float> in, std::span<float> out,
                  std::vector<std::vector<float>>& bufChain);
    void recomputeNorm();

    int points_ = 129;
    int passes_ = 3;
    int samplesInInput_ = 512;
    float gainDb_ = 0.0F;
    float norm_ = 1.0F;

    // passBuffers_[0]   — input history (PushArray destination).
    // passBuffers_[i]   — output of the i-th pass.
    // Each row has length `samplesInInput_ + points_`.
    std::vector<std::vector<float>> bufRe_;
    std::vector<std::vector<float>> bufIm_;
};

}  // namespace mr::dsp
