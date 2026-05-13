// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Agc.h"

#include "core/Constants.h"

#include <algorithm>
#include <cmath>

namespace mr::dsp {

namespace {
constexpr float kEnvelopeFloor = 1.0e-10F;
}  // namespace

Agc::Agc() {
    rebuildAttackShape();
    recomputeBeta();
}

void Agc::setNoiseInDb(float db) {
    // Pascal: FNoiseIn := Power(10, 0.05 * Value).
    noiseIn_ = std::pow(10.0F, 0.05F * db);
    recomputeBeta();
}

void Agc::setNoiseOutDb(float db) {
    // Pascal clamps NoiseOut to 25% of MaxOut to keep the AGC curve's
    // exponent well-defined.
    const float candidate = std::pow(10.0F, 0.05F * db);
    noiseOut_ = std::min(0.25F * maxOut_, candidate);
    recomputeBeta();
}

void Agc::setMaxOut(float maxOut) {
    if (maxOut <= 0.0F) {
        return;
    }
    maxOut_ = maxOut;
    recomputeBeta();
}

void Agc::setAttackSamples(int n) {
    attackSamples_ = std::max(1, n);
    rebuildAttackShape();
}

void Agc::setHoldSamples(int n) {
    holdSamples_ = std::max(1, n);
    rebuildAttackShape();
}

void Agc::recomputeBeta() {
    // Pascal: FBeta := FNoiseIn / Ln(FMaxOut / (FMaxOut - FNoiseOut)).
    // This solves the equation NoiseOut = MaxOut · (1 - exp(-NoiseIn / Beta))
    // for Beta, so the linear-region gain matches the requested ratio.
    if (noiseOut_ < maxOut_) {
        beta_ = noiseIn_ / std::log(maxOut_ / (maxOut_ - noiseOut_));
    } else {
        beta_ = noiseIn_;
    }
    defaultGain_ = (noiseIn_ > 0.0F) ? (noiseOut_ / noiseIn_) : 1.0F;
}

void Agc::rebuildAttackShape() {
    // Pascal: FLen := 2 * (FAttackSamples + FHoldSamples) + 1; attack
    // shape is a half-cosine rising window in log space, mirrored on
    // the trailing side so the look-ahead and look-back are symmetric.
    len_ = 2 * (attackSamples_ + holdSamples_) + 1;
    attackShape_.assign(static_cast<std::size_t>(len_), 0.0F);
    for (int i = 0; i < attackSamples_; ++i) {
        const double phase = (i + 1) * mr::constants::Math::kPi
                             / static_cast<double>(attackSamples_ + 1);
        const float val = static_cast<float>(std::log(0.5 - 0.5 * std::cos(phase)));
        attackShape_[static_cast<std::size_t>(i)] = val;
        attackShape_[static_cast<std::size_t>(len_ - 1 - i)] = val;
    }
    reset();
}

void Agc::reset() {
    realBuf_.assign(static_cast<std::size_t>(len_), 0.0F);
    magBuf_.assign(static_cast<std::size_t>(len_), 0.0F);
    bufIdx_ = 0;
}

float Agc::calcAgcGain() {
    // Look ±len/2 around the current sample; take the maximum of
    // log-mag plus the attack-shape weight. The exponentiation then
    // converts back to linear envelope; the standard 1-exp(-env/Beta)
    // soft-knee curve gives the gain.
    float envelLog = -23.025851F;  // ln(1e-10) — Pascal's "envelope floor".
    int idx = bufIdx_;
    for (int wi = 0; wi < len_; ++wi) {
        const float sample = magBuf_[static_cast<std::size_t>(idx)]
                             + attackShape_[static_cast<std::size_t>(wi)];
        if (sample > envelLog) {
            envelLog = sample;
        }
        ++idx;
        if (idx == len_) {
            idx = 0;
        }
    }
    const float envel = std::exp(envelLog);
    return maxOut_ * (1.0F - std::exp(-envel / beta_)) / envel;
}

float Agc::applyAgc(float v) {
    realBuf_[static_cast<std::size_t>(bufIdx_)] = v;
    magBuf_[static_cast<std::size_t>(bufIdx_)] =
        std::log(std::abs(v) + kEnvelopeFloor);

    bufIdx_ = (bufIdx_ + 1) % len_;
    const int mid = (bufIdx_ + (len_ / 2)) % len_;
    return realBuf_[static_cast<std::size_t>(mid)] * calcAgcGain();
}

void Agc::process(std::span<float> data) {
    overload_ = false;
    if (enabled_) {
        for (float& s : data) {
            s = applyAgc(s);
        }
    } else {
        for (float& s : data) {
            const float scaled = s * defaultGain_;
            const float clamped = std::clamp(scaled, -maxOut_, maxOut_);
            if (std::abs(clamped) == maxOut_) {
                overload_ = true;
            }
            s = clamped;
        }
    }
}

}  // namespace mr::dsp
