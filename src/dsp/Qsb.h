// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Qsb.pas. Per-station Rayleigh-fading model: takes two uniform
// noise streams, low-passes both through a QuickAverage configured for
// the requested fading bandwidth, and uses the magnitude of the result
// as a slowly-varying amplitude multiplier. Applied across each station's
// rendered keying envelope to give the audible "QSB" effect.

#pragma once

#include "dsp/QuickAverage.h"

#include <span>

namespace mr::core {
class Random;
}

namespace mr::dsp {

class Qsb {
public:
    // `bufSize` mirrors Ini.BufSize — the gain is updated in groups of
    // `bufSize/4` samples (the original's pacing, kept for parity).
    Qsb(int bufSize, mr::core::Random& rng);

    void setBandwidth(float bandwidthHz);
    [[nodiscard]] float bandwidth() const noexcept { return bandwidth_; }

    // Multiplies each sample by a Rayleigh-distributed amplitude that
    // varies smoothly at the configured bandwidth.
    void applyTo(std::span<float> arr);

    // Probability that this station also gets "flutter" (faster fading);
    // owner sets bandwidth via setBandwidth(3..33) in that case.

private:
    [[nodiscard]] float newGain();

    int bufSize_;
    int subBlockSize_;             // Pascal: BufSize div 4
    float bandwidth_ = 0.1F;
    float gain_ = 1.0F;
    float qsbLevel_ = 1.0F;
    QuickAverage filt_;
    mr::core::Random& rng_;
};

}  // namespace mr::dsp
