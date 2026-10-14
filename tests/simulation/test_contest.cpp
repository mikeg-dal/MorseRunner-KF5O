// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/Contest.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "simulation/CallsignSource.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace mr::sim;

namespace {

constexpr int kBuf = mr::constants::Audio::kDefaultBufferSamples;

}  // namespace

TEST(Contest, RenderInStopModeIsSilence) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(1);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    std::vector<float> buf(kBuf, 99.0F);
    const std::size_t n = contest.renderNextBlock(buf);
    EXPECT_EQ(n, static_cast<std::size_t>(kBuf));
    for (const float s : buf) {
        EXPECT_FLOAT_EQ(s, 0.0F);
    }
}

TEST(Contest, FirstBlocksAreSilenceForStartupSkip) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(2);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    std::vector<float> buf(kBuf, 99.0F);
    // Pascal: skip first 5 (kStartupSkipBlocks = 6, condition is < 6).
    for (int b = 0; b < mr::constants::Audio::kStartupSkipBlocks - 1; ++b) {
        std::fill(buf.begin(), buf.end(), 99.0F);
        contest.renderNextBlock(buf);
        for (const float s : buf) {
            EXPECT_FLOAT_EQ(s, 0.0F) << "block " << b;
        }
    }
}

TEST(Contest, ProducesBoundedAudioAfterStartupSkip) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(42);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);

    std::vector<float> buf(kBuf, 0.0F);
    // Run for 50 blocks (~2.3 seconds at default buffer/SR). Output
    // should be bounded; specifically ≤ 1.0 magnitude (Float-PCM
    // range), no NaN, no Inf.
    bool anyNonZero = false;
    for (int b = 0; b < 50; ++b) {
        contest.renderNextBlock(buf);
        for (const float s : buf) {
            EXPECT_TRUE(std::isfinite(s));
            EXPECT_LE(std::abs(s), 1.5F);  // small AGC headroom slop
            if (s != 0.0F) anyNonZero = true;
        }
    }
    EXPECT_TRUE(anyNonZero) << "Expected audible content within 50 blocks";
}

TEST(Contest, EndOfSessionFiresAtDurationLimit) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(7);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    ContestSettings s;
    s.durationMinutes = 0;  // duration < 1 minute → ends after 1st block
    contest.setSettings(s);
    contest.setRunMode(RunMode::PileUp);

    bool fired = false;
    contest.setEndOfSessionCallback([&](RunMode m) {
        fired = true;
        EXPECT_EQ(m, RunMode::PileUp);
    });

    std::vector<float> buf(kBuf, 0.0F);
    // Drive enough blocks for elapsed > 0 (kStartupSkipBlocks=6).
    for (int b = 0; b < 12 && !fired; ++b) {
        contest.renderNextBlock(buf);
    }
    EXPECT_TRUE(fired);
    // After end-of-session the mode returns to Stop.
    EXPECT_EQ(contest.runMode(), RunMode::Stop);
}

TEST(Contest, RequestStopForcesEndOfSession) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(11);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    bool fired = false;
    contest.setEndOfSessionCallback([&](RunMode) { fired = true; });
    contest.requestStop();
    std::vector<float> buf(kBuf, 0.0F);
    for (int b = 0; b < 12 && !fired; ++b) {
        contest.renderNextBlock(buf);
    }
    EXPECT_TRUE(fired);
}

TEST(Contest, PileUpStartsSilentUntilPlayerCq) {
    // Pascal parity: starting Pile-Up keys nothing, so no callers
    // appear until the player sends CQ (F1).
    auto& rng = mr::core::Random::instance();
    rng.reseed(1234);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    EXPECT_NE(contest.player().state(), StationState::Sending);
    std::vector<float> buf(kBuf, 0.0F);
    for (int b = 0; b < 500; ++b) {
        contest.renderNextBlock(buf);
    }
    EXPECT_EQ(contest.stations().dxCount(), 0U);
}

TEST(Contest, PileUpPlayerCqDrawsCallers) {
    // Once the player's CQ finishes, the Poisson spawn in
    // onMeFinishedSending should put callers on the band.
    auto& rng = mr::core::Random::instance();
    rng.reseed(1234);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    contest.playerSendMessage(Message::Cq);
    std::vector<float> buf(kBuf, 0.0F);
    bool sawCaller = false;
    for (int b = 0; b < 500 && !sawCaller; ++b) {
        contest.renderNextBlock(buf);
        sawCaller = contest.stations().dxCount() > 0;
    }
    EXPECT_TRUE(sawCaller);
}

TEST(Contest, KeysPressedWhileStoppedAreDroppedOnRun) {
    // F1 in Stop mode must not queue a CQ that fires once Run starts.
    auto& rng = mr::core::Random::instance();
    rng.reseed(5);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::Stop);
    contest.playerSendMessage(Message::Cq);
    contest.playerSendMessage(Message::Cq);
    contest.setRunMode(RunMode::PileUp);
    EXPECT_NE(contest.player().state(), StationState::Sending);
}
