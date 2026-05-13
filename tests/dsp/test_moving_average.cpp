// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MovingAverage.h"

#include "dsp/ComplexBuf.h"

#include <gtest/gtest.h>

#include <numeric>
#include <vector>

using namespace mr::dsp;

namespace {

constexpr int kPoints = 16;
constexpr int kPasses = 3;
constexpr int kBlockSize = 64;

}  // namespace

TEST(MovingAverage, ImpulseEnergyConservation) {
    // Feed a single impulse on the first sample; total energy out (over
    // many blocks until the impulse has fully propagated) should equal
    // the input energy when gainDb=0 — the filter normalization is set
    // up to make the cascade unity-gain.
    MovingAverage mavg;
    mavg.configure(kPoints, kPasses, kBlockSize, 0.0F);

    std::vector<float> in(kBlockSize, 0.0F);
    in[0] = 1.0F;
    std::vector<float> out(kBlockSize, 0.0F);
    double total = 0.0;

    // Run enough blocks for the entire (Points * Passes)-length impulse
    // response to clear the delay line.
    for (int b = 0; b < 8; ++b) {
        mavg.process(in, out);
        for (const float s : out) {
            total += static_cast<double>(s);
        }
        std::fill(in.begin(), in.end(), 0.0F);
    }
    EXPECT_NEAR(total, 1.0, 1.0e-4);
}

TEST(MovingAverage, DCResponseEqualsOne) {
    // A constant input of 1.0 should produce an output that converges
    // to 1.0 once the delay line is full. Verified after enough warm-up
    // blocks that the recursive sum is fully primed.
    MovingAverage mavg;
    mavg.configure(kPoints, kPasses, kBlockSize, 0.0F);

    std::vector<float> in(kBlockSize, 1.0F);
    std::vector<float> out(kBlockSize, 0.0F);
    for (int b = 0; b < 16; ++b) {
        mavg.process(in, out);
    }
    for (const float s : out) {
        EXPECT_NEAR(s, 1.0F, 1.0e-5F);
    }
}

TEST(MovingAverage, ResetZeroesState) {
    MovingAverage mavg;
    mavg.configure(kPoints, kPasses, kBlockSize, 0.0F);

    std::vector<float> in(kBlockSize, 1.0F);
    std::vector<float> out(kBlockSize, 0.0F);
    for (int b = 0; b < 4; ++b) {
        mavg.process(in, out);
    }
    mavg.reset();
    // Right after reset, with zero input, the output should be zero.
    std::fill(in.begin(), in.end(), 0.0F);
    mavg.process(in, out);
    for (const float s : out) {
        EXPECT_FLOAT_EQ(s, 0.0F);
    }
}

TEST(MovingAverage, ComplexProcessesReAndImIndependently) {
    MovingAverage mavg;
    mavg.configure(kPoints, kPasses, kBlockSize, 0.0F);

    ComplexBuf buf;
    buf.resize(kBlockSize);
    // Re channel gets an impulse; Im stays zero.
    buf.re[0] = 1.0F;
    mavg.processComplex(buf);

    // Im output must remain zero everywhere (independent delay lines).
    for (const float s : buf.im) {
        EXPECT_FLOAT_EQ(s, 0.0F);
    }
}
