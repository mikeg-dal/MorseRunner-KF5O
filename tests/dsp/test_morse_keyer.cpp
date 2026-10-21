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

// Delphi Round() rounds exact halves to even. 13230 / WPM is an exact
// .5 at 12, 28 and 60 WPM; Pascal gets 1102 / 472 / 220 samples per unit.
TEST(MorseKeyer, SamplesPerUnitUsesDelphiRounding) {
    EXPECT_EQ(MorseKeyer(kSampleRate, 12).samplesPerUnit(), 1102);
    EXPECT_EQ(MorseKeyer(kSampleRate, 28).samplesPerUnit(), 472);
    EXPECT_EQ(MorseKeyer(kSampleRate, 60).samplesPerUnit(), 220);
}

// Above ~88 WPM a unit is shorter than the 149-sample ramp. Pascal moves
// its write pointer backwards there and lets the ramps overlap; the port
// used to run past the end of the buffer (heap overflow under ASan).
TEST(MorseKeyer, HighSpeedEnvelopeStaysInBounds) {
    for (int wpm = 85; wpm <= 120; ++wpm) {
        MorseKeyer k(kSampleRate, wpm);
        const auto env = k.renderEnvelope("HHHHH 55555 CQ TEST VE3NEA");
        ASSERT_FALSE(env.empty()) << "wpm " << wpm;
        const float peak = *std::max_element(env.begin(), env.end());
        EXPECT_GT(peak, 0.5F) << "wpm " << wpm;
        for (const float s : env) {
            ASSERT_GE(s, 0.0F) << "wpm " << wpm;
            ASSERT_LE(s, 1.0F) << "wpm " << wpm;
        }
    }
}
