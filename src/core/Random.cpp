// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "core/Random.h"

#include "core/Constants.h"
#include "core/Logging.h"

#include <QtGlobal>

#include <algorithm>
#include <cmath>

namespace mr::core {

namespace {
    constexpr float kFloatOne = 1.0f;
    constexpr float kTinyEpsilon = 1.0e-12f;
}  // namespace

Random& Random::instance() {
    static Random r;
    return r;
}

Random::Random() {
    std::random_device rd;
    // 64-bit seed from two 32-bit draws so MT19937's state is well excited.
    seed_ = (static_cast<std::uint64_t>(rd()) << 32) | rd();
    rng_.seed(static_cast<std::mt19937::result_type>(seed_));
    qInfo(mrSim) << "Random seed:" << QString::number(seed_, 16);
}

void Random::reseed(std::uint64_t s) noexcept {
    seed_ = s;
    rng_.seed(static_cast<std::mt19937::result_type>(s));
    hasSparedNormal_ = false;
}

float Random::uniform01() noexcept {
    // We want a closed-open [0, 1) draw with full 24-bit precision. The
    // std::uniform_real_distribution<float> can in rare implementations
    // return exactly 1.0f, which would break the log() in rayleigh() — so
    // we generate manually from a 32-bit integer and divide.
    constexpr float kInv2Pow32 = 1.0f / 4294967296.0f;
    return static_cast<float>(rng_()) * kInv2Pow32;
}

int Random::uniformInt(int n) noexcept {
    if (n <= 0) {
        return 0;
    }
    std::uniform_int_distribution<int> dist(0, n - 1);
    return dist(rng_);
}

float Random::normal() noexcept {
    // Box-Muller, caching the second sample of each pair. Matches Delphi
    // RndNormal in distribution; sample sequence differs (MT19937 vs LCG).
    if (hasSparedNormal_) {
        hasSparedNormal_ = false;
        return sparedNormal_;
    }
    float u1 = uniform01();
    const float u2 = uniform01();
    // Defend against u1 == 0 — would produce -inf through the log.
    if (u1 < kTinyEpsilon) {
        u1 = kTinyEpsilon;
    }
    const float radius = std::sqrt(-2.0f * std::log(u1));
    const float angle = static_cast<float>(mr::constants::Math::kTwoPi) * u2;
    sparedNormal_ = radius * std::sin(angle);
    hasSparedNormal_ = true;
    return radius * std::cos(angle);
}

float Random::gaussLim(float mean, float lim) noexcept {
    const float candidate = mean + normal() * 0.5f * lim;
    return std::clamp(candidate, mean - lim, mean + lim);
}

float Random::rayleigh(float mean) noexcept {
    // Sum of two -log(U) draws → magnitude of a 2D Gaussian with σ=1,
    // scaled to the requested mean. Pascal: RndRayleigh.
    float u1 = uniform01();
    float u2 = uniform01();
    if (u1 < kTinyEpsilon) {
        u1 = kTinyEpsilon;
    }
    if (u2 < kTinyEpsilon) {
        u2 = kTinyEpsilon;
    }
    return mean * std::sqrt(-std::log(u1) - std::log(u2));
}

int Random::poisson(float mean) noexcept {
    // Knuth's product algorithm. Numerically stable for the small λ values
    // (≤ Activity/2 with Activity ≤ 9 → λ ≤ 4.5) the simulator uses.
    if (mean <= 0.0f) {
        return 0;
    }
    const float threshold = std::exp(-mean);
    float product = kFloatOne;
    int k = 0;
    while (true) {
        product *= uniform01();
        if (product < threshold) {
            return k;
        }
        ++k;
        // Guard against pathological loops if mean is corrupted; in normal
        // operation k stays well under 30 for λ < 5.
        if (k > 1024) {
            return k;
        }
    }
}

float Random::uShaped() noexcept {
    // sin(π·(u - ½)) — peaks at ±1, dips to 0 at u = ½.
    const float u = uniform01();
    return std::sin(static_cast<float>(mr::constants::Math::kPi) * (u - 0.5f));
}

}  // namespace mr::core
