// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Qsb.h"

#include "core/Random.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace mr::dsp;

TEST(Qsb, ApplyIsFiniteAndBounded) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(42);
    Qsb qsb(512, rng);
    qsb.setBandwidth(0.2F);
    std::vector<float> sig(2048, 1.0F);
    qsb.applyTo(sig);
    for (const float s : sig) {
        EXPECT_TRUE(std::isfinite(s));
        // Rayleigh-distributed; very rare tails above 5 are still
        // bounded by the points-scaled cap.
        EXPECT_LT(std::abs(s), 50.0F);
    }
}

TEST(Qsb, NonZeroVariance) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(7);
    Qsb qsb(512, rng);
    qsb.setBandwidth(0.2F);
    std::vector<float> sig(4096, 1.0F);
    qsb.applyTo(sig);
    double mean = 0.0;
    for (const float s : sig) {
        mean += static_cast<double>(s);
    }
    mean /= static_cast<double>(sig.size());
    double var = 0.0;
    for (const float s : sig) {
        const double d = static_cast<double>(s) - mean;
        var += d * d;
    }
    var /= static_cast<double>(sig.size());
    EXPECT_GT(var, 0.0);
}

TEST(Qsb, FlutterBandwidthAccepted) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(1);
    Qsb qsb(512, rng);
    qsb.setBandwidth(15.0F);
    EXPECT_FLOAT_EQ(qsb.bandwidth(), 15.0F);
}
