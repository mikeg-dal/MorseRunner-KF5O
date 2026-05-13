// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Qsb.h"

#include "core/Constants.h"
#include "core/Random.h"

#include <algorithm>
#include <cmath>

namespace mr::dsp {

namespace {

constexpr int kSubBlockDivisor = 4;
constexpr float kPointsCoef = 0.37F;

}  // namespace

Qsb::Qsb(int bufSize, mr::core::Random& rng) : bufSize_(bufSize), rng_(rng) {
    subBlockSize_ = std::max(1, bufSize / kSubBlockDivisor);
    filt_.setPasses(3);
    setBandwidth(0.1F);
}

void Qsb::setBandwidth(float bandwidthHz) {
    if (bandwidthHz <= 0.0F) {
        return;
    }
    bandwidth_ = bandwidthHz;
    // Pascal: Filt.Points := Ceil(0.37 * DEFAULTRATE / ((BufSize div 4) * Value)).
    // The bandwidth maps inversely to the filter length: narrower fade
    // = longer averaging window.
    const double sr = static_cast<double>(mr::constants::Audio::kSampleRate);
    const double denom = static_cast<double>(subBlockSize_) * static_cast<double>(bandwidthHz);
    const int points = std::max(1, static_cast<int>(std::ceil(kPointsCoef * sr / denom)));
    filt_.setPoints(points);
    // Warm up so the first audible block is already at a settled gain.
    for (int i = 0; i <= points * 3; ++i) {
        gain_ = newGain();
    }
}

float Qsb::newGain() {
    // Pascal: Filt.Filter(RndUniform, RndUniform) returns a complex
    // result; its magnitude (scaled by √(3·Points)) is a Rayleigh-
    // distributed amplitude. The further scaling by qsbLevel + (1-lvl)
    // mixes between full fading and unity (defaults to qsbLevel=1).
    const float u1 = 2.0F * rng_.uniform01() - 1.0F;
    const float u2 = 2.0F * rng_.uniform01() - 1.0F;
    float reOut = 0.0F;
    float imOut = 0.0F;
    filt_.filterComplex(u1, u2, reOut, imOut);
    const float magSq = reOut * reOut + imOut * imOut;
    float g = std::sqrt(magSq * 3.0F * static_cast<float>(filt_.points()));
    g = g * qsbLevel_ + (1.0F - qsbLevel_);
    return g;
}

void Qsb::applyTo(std::span<float> arr) {
    const int blkCnt = static_cast<int>(arr.size() / static_cast<std::size_t>(subBlockSize_));
    for (int b = 0; b < blkCnt; ++b) {
        const float target = newGain();
        const float dG = (target - gain_) / static_cast<float>(subBlockSize_);
        const std::size_t base = static_cast<std::size_t>(b) * static_cast<std::size_t>(subBlockSize_);
        for (int i = 0; i < subBlockSize_; ++i) {
            arr[base + static_cast<std::size_t>(i)] *= gain_;
            gain_ += dG;
        }
    }
}

}  // namespace mr::dsp
