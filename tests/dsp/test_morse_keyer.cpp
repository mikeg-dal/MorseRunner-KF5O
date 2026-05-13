// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MorseKeyer.h"

#include "core/Constants.h"
#include "dsp/MorseTable.h"

#include <gtest/gtest.h>

#include <algorithm>

using namespace mr::dsp;
using mr::constants::Audio::kSampleRate;

TEST(MorseKeyer, SamplesPerUnitAtDefault) {
    MorseKeyer k(kSampleRate, 30);
    // SamplesInUnit = round(0.1 * 11025 * 12 / 30) = round(441) = 441.
    EXPECT_EQ(k.samplesPerUnit(), 441);
}

TEST(MorseKeyer, RampLengthAtDefault) {
    MorseKeyer k(kSampleRate, 30);
    // RampLen = round(2.7 * 0.005 * 11025) = round(148.84) = 149.
    EXPECT_EQ(k.rampSamples(), 149);
}

TEST(MorseKeyer, EnvelopeLengthMatchesUnits) {
    MorseKeyer k(kSampleRate, 30);
    // 'E' encodes to ". " → '~' replaces the trailing space → ".~".
    // Unit count: '.'=2 + '~'=1 = 3 units. EnvLen = 3·441 + 149 = 1472.
    const auto env = k.renderEnvelope("E");
    EXPECT_EQ(env.size(), 3U * 441U + 149U);
}

TEST(MorseKeyer, EnvelopeStartsRampsAndPeaks) {
    MorseKeyer k(kSampleRate, 30);
    const auto env = k.renderEnvelope("E");
    ASSERT_FALSE(env.empty());
    // First sample is the integrated BH kernel evaluated at x=0 after
    // tail normalization — small but not exactly zero. < 1e-3 keeps key
    // clicks inaudible while leaving headroom for FP noise.
    EXPECT_LT(env.front(), 1.0e-3F);
    EXPECT_GE(env.front(), 0.0F);
    const float peak = *std::max_element(env.begin(), env.end());
    EXPECT_FLOAT_EQ(peak, 1.0F);
}

TEST(MorseKeyer, RangeIsZeroToOne) {
    MorseKeyer k(kSampleRate, 30);
    const auto env = k.renderEnvelope("CQ TEST");
    for (const float s : env) {
        EXPECT_GE(s, 0.0F);
        EXPECT_LE(s, 1.0F);
    }
}

TEST(MorseKeyer, WpmChangesSampleCount) {
    MorseKeyer k(kSampleRate, 30);
    const std::size_t at30 = k.renderEnvelope("PARIS").size();
    k.setWpm(60);
    const std::size_t at60 = k.renderEnvelope("PARIS").size();
    EXPECT_LT(at60, at30);
}

TEST(MorseKeyer, EmptyMessageReturnsEmpty) {
    MorseKeyer k(kSampleRate, 30);
    EXPECT_TRUE(k.renderEnvelope("").empty());
}
