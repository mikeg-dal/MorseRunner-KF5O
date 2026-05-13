// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/QuickAverage.h"

#include <gtest/gtest.h>

#include <cmath>

using namespace mr::dsp;

TEST(QuickAverage, DefaultsMatchPascal) {
    QuickAverage q;
    EXPECT_EQ(q.points(), 128);
    EXPECT_EQ(q.passes(), 4);
}

TEST(QuickAverage, ZeroInputProducesZeroOutput) {
    QuickAverage q;
    q.setPoints(16);
    q.setPasses(2);
    for (int i = 0; i < 200; ++i) {
        EXPECT_FLOAT_EQ(q.filter(0.0F), 0.0F);
    }
}

TEST(QuickAverage, DcInputConvergesToOne) {
    // 4-pass cumulative-sum averaging settles to the mean of the input
    // window once the delay lines are full. Constant 1.0 in → output
    // converges to ~1.0 after many points · passes samples.
    QuickAverage q;
    q.setPoints(16);
    q.setPasses(2);
    float lastOut = 0.0F;
    for (int i = 0; i < 4096; ++i) {
        lastOut = q.filter(1.0F);
    }
    EXPECT_NEAR(lastOut, 1.0F, 1.0e-3F);
}

TEST(QuickAverage, PassesClampedTo8) {
    QuickAverage q;
    q.setPasses(20);
    EXPECT_LE(q.passes(), 8);
}
