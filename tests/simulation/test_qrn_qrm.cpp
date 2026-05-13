// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/QrmStation.h"
#include "simulation/QrnStation.h"

#include "FakeEngine.h"

#include <gtest/gtest.h>

#include <vector>

using namespace mr::sim;
using mr::sim::test::FakeEngine;

TEST(QrnStation, ConstructsInSendingStateWithEnvelope) {
    FakeEngine eng;
    eng.random().reseed(7);
    QrnStation qrn(&eng);
    EXPECT_EQ(qrn.state(), StationState::Sending);
    // Burst can be empty if Random picks a near-zero duration; we
    // just verify the state is correct and the station starts sending.
}

TEST(QrnStation, FinishesAfterEnvelopeExhausted) {
    FakeEngine eng;
    eng.random().reseed(123);
    QrnStation qrn(&eng);
    EXPECT_FALSE(qrn.isFinished());
    // Drain the envelope by repeatedly calling getBlock + tick. Bound
    // the loop so an infinite-loop bug doesn't hang the test.
    std::vector<float> buf(512, 0.0F);
    for (int i = 0; i < 10000 && !qrn.isFinished(); ++i) {
        qrn.getBlock(buf);
        qrn.tick();
    }
    EXPECT_TRUE(qrn.isFinished());
}

TEST(QrmStation, ConstructsInSendingState) {
    FakeEngine eng;
    eng.random().reseed(5);
    QrmStation qrm(&eng, "JA1XYZ");
    EXPECT_EQ(qrm.state(), StationState::Sending);
    EXPECT_EQ(qrm.myCall(), "JA1XYZ");
    EXPECT_EQ(qrm.hisCall(), eng.myCallsign());
    // Pascal: Wpm in [30, 50).
    EXPECT_GE(qrm.wpm(), 30);
    EXPECT_LT(qrm.wpm(), 50);
    // Pascal: Amplitude in [5000, 30000).
    EXPECT_GE(qrm.amplitude(), 5000.0F);
    EXPECT_LT(qrm.amplitude(), 30000.0F);
}

TEST(QrmStation, FinishesAfterPatienceRunsOut) {
    FakeEngine eng;
    eng.random().reseed(99);
    QrmStation qrm(&eng, "JA1XYZ");
    // Fire MsgSent up to 6 times — patience is in [1, 5] so at most
    // 5 sends before isFinished() becomes true.
    for (int i = 0; i < 6 && !qrm.isFinished(); ++i) {
        qrm.processEvent(StationEvent::MsgSent);
    }
    EXPECT_TRUE(qrm.isFinished());
}

TEST(QrmStation, IgnoresMeStartedAndMeFinished) {
    FakeEngine eng;
    eng.random().reseed(99);
    QrmStation qrm(&eng, "JA1XYZ");
    const StationState before = qrm.state();
    qrm.processEvent(StationEvent::MeStarted);
    qrm.processEvent(StationEvent::MeFinished);
    EXPECT_EQ(qrm.state(), before);
    EXPECT_FALSE(qrm.isFinished());
}
