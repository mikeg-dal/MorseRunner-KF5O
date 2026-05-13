// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Agc.h"

#include <gtest/gtest.h>

#include <cmath>
#include <vector>

using namespace mr::dsp;

TEST(Agc, BypassedAppliesDefaultGain) {
    Agc agc;
    agc.setMaxOut(20000.0F);
    agc.setNoiseInDb(0.0F);
    agc.setNoiseOutDb(60.0F);  // gain ≈ 1000
    agc.setEnabled(false);

    std::vector<float> data(64, 1.0F);
    agc.process(data);
    // defaultGain_ = noiseOut_/noiseIn_ = 1000.0
    for (const float s : data) {
        EXPECT_NEAR(s, 1000.0F, 1.0F);
    }
}

TEST(Agc, BypassedClampsToMaxOut) {
    Agc agc;
    agc.setMaxOut(20000.0F);
    agc.setNoiseInDb(0.0F);
    agc.setNoiseOutDb(60.0F);
    agc.setEnabled(false);
    std::vector<float> data{50.0F, -50.0F, 100.0F};
    agc.process(data);
    EXPECT_EQ(data[0], 20000.0F);
    EXPECT_EQ(data[1], -20000.0F);
    EXPECT_EQ(data[2], 20000.0F);
    EXPECT_TRUE(agc.isOverload());
}

TEST(Agc, EnabledStaysFiniteOnStep) {
    Agc agc;
    agc.setMaxOut(20000.0F);
    agc.setNoiseInDb(0.0F);
    agc.setNoiseOutDb(60.0F);
    agc.setAttackSamples(155);
    agc.setHoldSamples(155);
    agc.setEnabled(true);

    // Step input from 0 to a large signal — AGC should attenuate the
    // resulting envelope without producing NaN or inf.
    std::vector<float> data(2048, 0.0F);
    for (std::size_t i = 512; i < data.size(); ++i) {
        data[i] = 10000.0F;
    }
    agc.process(data);
    for (const float s : data) {
        EXPECT_TRUE(std::isfinite(s)) << "non-finite sample";
    }
}

TEST(Agc, ResetClearsDelayLine) {
    Agc agc;
    agc.setMaxOut(20000.0F);
    agc.setNoiseInDb(0.0F);
    agc.setNoiseOutDb(60.0F);
    agc.setEnabled(true);

    std::vector<float> hot(2048, 10000.0F);
    agc.process(hot);
    agc.reset();
    std::vector<float> cold(2048, 0.0F);
    agc.process(cold);
    // After reset + zero input the output magnitude should be ~zero
    // (small floor from log(0+ε) is acceptable but unmissably small).
    for (const float s : cold) {
        EXPECT_LT(std::abs(s), 1.0F);
    }
}
