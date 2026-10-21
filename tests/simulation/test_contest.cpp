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
    contest.setEndOfSessionCallback([&](RunMode m, bool byUser) {
        fired = true;
        EXPECT_EQ(m, RunMode::PileUp);
        EXPECT_FALSE(byUser);
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
    contest.setEndOfSessionCallback([&](RunMode, bool byUser) {
        fired = true;
        EXPECT_TRUE(byUser);  // Pascal FStopPressed
    });
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

namespace {

// True if any DX caller is transmitting within `blocks` blocks.
bool aDxCallsWithin(Contest& contest, int blocks) {
    std::vector<float> buf(kBuf, 0.0F);
    for (int b = 0; b < blocks; ++b) {
        contest.renderNextBlock(buf);
        for (auto& s : contest.stations()) {
            if (dynamic_cast<DxStation*>(s.get()) != nullptr
                && s->state() == StationState::Sending) {
                return true;
            }
        }
    }
    return false;
}

}  // namespace

// Pascal Contest.GetAudio hands each auto-spawned Single Calls / HST
// caller an evMeFinished (with Me.Msg = [msgCQ]) so it calls on its own.
// The player never presses a key in these tests.
TEST(Contest, SingleCallsCallerCallsWithoutPlayerInput) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(7);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::Single);
    // ~10 s of audio; GetSendDelay is well under that.
    EXPECT_TRUE(aDxCallsWithin(contest, 220));
}

TEST(Contest, HstCallersCallWithoutPlayerInput) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(8);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::Hst);
    EXPECT_TRUE(aDxCallsWithin(contest, 220));
}

// Pascal Log.SaveQso ends with Inc(Tst.Me.NR); Run resets it to 1.
TEST(Contest, SerialNumberAdvancesPerLoggedQso) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(21);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    EXPECT_EQ(contest.player().nr(), 1);
    contest.qsoLogged("W1AW");
    contest.qsoLogged("K2ABC");
    EXPECT_EQ(contest.player().nr(), 3);
    contest.setRunMode(RunMode::Stop);
    contest.setRunMode(RunMode::PileUp);
    EXPECT_EQ(contest.player().nr(), 1);
}

// Pascal TMainForm.SendMsg: Me.HisCall follows the Call box only when
// HisCall is sent, and an empty box keeps the previous call.
TEST(Contest, HisCallIsWhatWasSent) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(22);
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setRunMode(RunMode::PileUp);
    contest.playerSendMessage(Message::HisCall, "w1aw");
    EXPECT_EQ(contest.heardCallsign(), "W1AW");
    contest.playerSendMessage(Message::HisCall, "");
    EXPECT_EQ(contest.heardCallsign(), "W1AW");
    // While the call is still queued, an edit replaces it
    // (UpdateCallInMessage: nothing of it has been keyed yet).
    EXPECT_TRUE(contest.playerEditedCall("K2ABC"));
    EXPECT_EQ(contest.heardCallsign(), "K2ABC");
    // Once nothing is being sent, typing does not change what the DX
    // compares against, and the GUI is told to clear CallSent.
    (void) contest.playerAbortSend();
    EXPECT_FALSE(contest.playerEditedCall("N3XYZ"));
    EXPECT_EQ(contest.heardCallsign(), "K2ABC");
}

// Pascal TContest.OnMeFinishedSending: TU + MyCall only counts as a CQ
// once something is in the log (QsoList <> nil).
TEST(Contest, TuMyCallDrawsCallersOnlyAfterFirstQso) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(23);
    ContestSettings s;
    s.activity = 9;  // Poisson(4.5): zero callers is very unlikely
    Contest contest(std::make_unique<HardcodedCallsignSource>(), kBuf, rng);
    contest.setSettings(s);
    contest.setRunMode(RunMode::PileUp);

    auto sendTuMyCallAndFinish = [&]() {
        contest.playerSendMessage(Message::Tu);
        contest.playerSendMessage(Message::MyCall);
        std::vector<float> buf(kBuf, 0.0F);
        for (int b = 0; b < 200 && contest.playerSending(); ++b) {
            contest.renderNextBlock(buf);
        }
        // One more block so the player's MsgSent fires.
        contest.renderNextBlock(buf);
    };

    sendTuMyCallAndFinish();
    EXPECT_EQ(contest.stations().dxCount(), 0U);

    contest.qsoLogged("W1AW");
    sendTuMyCallAndFinish();
    EXPECT_GT(contest.stations().dxCount(), 0U);
}
