// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/BlackmanHarris.h"

#include <gtest/gtest.h>

using namespace mr::dsp;

TEST(BlackmanHarris, EmptyOnZeroLength) {
    EXPECT_TRUE(blackmanHarrisStep(0).empty());
}

TEST(BlackmanHarris, EndsAtOne) {
    const auto r = blackmanHarrisStep(149);
    ASSERT_FALSE(r.empty());
    EXPECT_FLOAT_EQ(r.back(), 1.0F);
}

TEST(BlackmanHarris, StartsNearZero) {
    const auto r = blackmanHarrisStep(149);
    // The integrated BH kernel starts with kernel(0) = a0-a1+a2-a3 which
    // is small but not zero; after normalization it should be well below
    // 1% of full scale.
    EXPECT_LT(r.front(), 0.01F);
    EXPECT_GE(r.front(), 0.0F);
}

TEST(BlackmanHarris, MonotonicallyIncreasing) {
    const auto r = blackmanHarrisStep(149);
    for (std::size_t i = 1; i < r.size(); ++i) {
        EXPECT_GE(r[i], r[i - 1]) << "non-monotone at index " << i;
    }
}

TEST(BlackmanHarris, RiseTimeMatchesDefault) {
    // RampLen = round(2.7 * 0.005 * 11025) = round(148.84) = 149.
    // Confirmed by the keyer at default settings; here we just verify
    // the function happily produces that length.
    EXPECT_EQ(blackmanHarrisStep(149).size(), 149U);
}
