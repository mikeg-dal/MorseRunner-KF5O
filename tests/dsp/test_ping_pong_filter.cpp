// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/PingPongFilter.h"

#include "core/Constants.h"
#include "dsp/ComplexBuf.h"

#include <gtest/gtest.h>

#include <cmath>

using namespace mr::dsp;
using mr::constants::Audio::kFilterSwapBlocks;

namespace {

constexpr int kPoints = 16;
constexpr int kPasses = 3;
constexpr int kBlockSize = 64;

ComplexBuf makeDcBuf() {
    ComplexBuf b;
    b.resize(kBlockSize);
    std::fill(b.re.begin(), b.re.end(), 1.0F);
    std::fill(b.im.begin(), b.im.end(), 1.0F);
    return b;
}

}  // namespace

TEST(PingPongFilter, ConfigureZeroesBlockCount) {
    PingPongFilter ppf;
    ppf.configure(kPoints, kPasses, kBlockSize, 0.0F);
    EXPECT_EQ(ppf.blockCount(), 0U);
}

TEST(PingPongFilter, ProcessIncrementsBlockCount) {
    PingPongFilter ppf;
    ppf.configure(kPoints, kPasses, kBlockSize, 0.0F);
    auto buf = makeDcBuf();
    ppf.process(buf);
    EXPECT_EQ(ppf.blockCount(), 1U);
    ppf.process(buf);
    EXPECT_EQ(ppf.blockCount(), 2U);
}

TEST(PingPongFilter, NoAudibleDiscontinuityAtSwap) {
    // The whole point of the ping-pong: the audible filter never has its
    // state Reset out from under it. We verify by running a steady DC
    // input across the swap boundary and asserting the output doesn't
    // jump at block kFilterSwapBlocks.
    PingPongFilter ppf;
    ppf.configure(kPoints, kPasses, kBlockSize, 0.0F);

    auto buf = makeDcBuf();
    // Warm up well past the impulse-response length.
    for (int b = 0; b < kFilterSwapBlocks - 1; ++b) {
        buf = makeDcBuf();
        ppf.process(buf);
    }
    // The block that triggers the swap.
    buf = makeDcBuf();
    ppf.process(buf);
    const float lastSampleBefore = buf.re.back();

    // The block immediately after the swap.
    buf = makeDcBuf();
    ppf.process(buf);
    const float firstSampleAfter = buf.re.front();

    // After a clean swap the output should still be near 1.0 (DC steady
    // state); the tolerance defends against the legitimate small jump
    // of the freshly promoted filter not being perfectly settled.
    EXPECT_NEAR(lastSampleBefore, 1.0F, 0.05F);
    EXPECT_NEAR(firstSampleAfter, 1.0F, 0.05F);
}
