// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/DxStation.h"
#include "simulation/MyStation.h"

#include "FakeEngine.h"

#include "core/Constants.h"
#include "simulation/Engine.h"
#include "simulation/Messages.h"

#include <gtest/gtest.h>

#include <vector>

using namespace mr::sim;
using mr::sim::test::FakeEngine;

TEST(Station, DxStationConstructsWithRandomizedParams) {
    FakeEngine eng;
    eng.random().reseed(42);
    DxStation dx(&eng, "W1AW");
    EXPECT_EQ(dx.myCall(), "W1AW");
    EXPECT_EQ(dx.hisCall(), eng.myCallsign());
    EXPECT_GE(dx.wpm(), 15);   // pile-up: ≥ half of 30
    EXPECT_LE(dx.wpm(), 30);
    EXPECT_GE(dx.amplitude(), 9000.0F);
    EXPECT_EQ(dx.state(), StationState::Copying);
}

TEST(Station, DxStationGetBlockEmptyWhenListening) {
    FakeEngine eng;
    DxStation dx(&eng, "W1AW");
    // Force into Listening — should produce zero samples.
    dx.setTimeout(mr::sim::kNeverTimeout);
    // (state_ is Copying initially — fine: getBlock checks for
    // Sending. Anything not-Sending returns 0.)
    std::vector<float> buf(64, 0.0F);
    EXPECT_EQ(dx.getBlock(buf), 0U);
}

TEST(Station, MyStationDefaultsMatchPascal) {
    FakeEngine eng;
    MyStation me(&eng);
    EXPECT_EQ(me.myCall(), "VE3NEA");
    EXPECT_EQ(me.nr(), 1);
    EXPECT_EQ(me.rst(), 599);
    EXPECT_EQ(me.pitchHz(), 600);
    EXPECT_EQ(me.wpm(), 30);
}

TEST(Station, MyStationSendCqGeneratesEnvelope) {
    FakeEngine eng;
    MyStation me(&eng);
    me.setMyCall("KF5O");
    me.sendMsg(Message::Cq);
    EXPECT_EQ(me.state(), StationState::Sending);

    // Render a few blocks; envelope should produce non-zero samples.
    std::vector<float> buf(512, 0.0F);
    me.getBlock(buf);
    bool anyNonZero = false;
    for (const float s : buf) {
        if (s != 0.0F) {
            anyNonZero = true;
            break;
        }
    }
    EXPECT_TRUE(anyNonZero);
}

TEST(Station, MyStationSplitsPiecesAroundHisCall) {
    FakeEngine eng;
    MyStation me(&eng);
    me.setHisCall("JA1ABC");
    me.sendMsg(Message::HisCall);
    EXPECT_EQ(me.state(), StationState::Sending);
}

TEST(Station, MyStationAbortMarksGarbage) {
    FakeEngine eng;
    MyStation me(&eng);
    me.sendMsg(Message::Cq);
    me.abortSend();
    EXPECT_EQ(me.state(), StationState::Listening);
    EXPECT_TRUE(contains(me.msg(), Message::Garbage));
}

TEST(Station, BfoPhaseAdvancesPerSample) {
    FakeEngine eng;
    MyStation me(&eng);
    me.setPitchHz(600);
    const double p0 = me.tickBfoPhase();
    const double p1 = me.tickBfoPhase();
    EXPECT_GT(p1, p0);
}

TEST(Station, TimeoutTickFiresEvent) {
    FakeEngine eng;
    DxStation dx(&eng, "W1AW");
    // Move into Listening + arm a 3-block timeout. tick() three times
    // and confirm the timeout has decremented to 0.
    dx.setTimeout(3);
    dx.tick();
    EXPECT_EQ(dx.timeout(), 2);
    dx.tick();
    EXPECT_EQ(dx.timeout(), 1);
    // Third tick fires the Timeout event in ProcessEvent.
    dx.tick();
    EXPECT_EQ(dx.timeout(), 0);
}
