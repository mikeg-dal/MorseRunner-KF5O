// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/StationCollection.h"

#include "FakeEngine.h"

#include <gtest/gtest.h>

using namespace mr::sim;
using mr::sim::test::FakeEngine;

TEST(StationCollection, FactoriesAddItems) {
    FakeEngine eng;
    eng.random().reseed(1);
    StationCollection sc;
    sc.addCaller(&eng, "W1AW");
    sc.addQrn(&eng);
    sc.addQrm(&eng, "JA1XYZ");
    EXPECT_EQ(sc.size(), 3U);
}

TEST(StationCollection, DxCountTracksOnlyDxStations) {
    FakeEngine eng;
    eng.random().reseed(1);
    StationCollection sc;
    sc.addCaller(&eng, "W1AW");
    sc.addCaller(&eng, "K2ABC");
    sc.addQrn(&eng);
    sc.addQrm(&eng, "JA1XYZ");
    EXPECT_EQ(sc.dxCount(), 2U);
}

TEST(StationCollection, SweepRemovesFinishedQrnStations) {
    FakeEngine eng;
    eng.random().reseed(2);
    StationCollection sc;
    sc.addCaller(&eng, "W1AW");
    auto* qrn = sc.addQrn(&eng);
    EXPECT_EQ(sc.size(), 2U);

    // Manually fire MsgSent on the QrnStation — it should mark itself
    // finished, and sweep() should remove it.
    qrn->processEvent(StationEvent::MsgSent);
    sc.sweep();
    EXPECT_EQ(sc.size(), 1U);
}

TEST(StationCollection, SweepRemovesFailedDxStation) {
    FakeEngine eng;
    eng.random().reseed(3);
    StationCollection sc;
    auto* dx = sc.addCaller(&eng, "W1AW");

    // Force the operator into Failed state directly.
    dx->operatorState().setState(OperatorState::Failed);
    EXPECT_TRUE(dx->isFinished());
    sc.sweep();
    EXPECT_EQ(sc.size(), 0U);
}

TEST(StationCollection, SweepKeepsLivingStations) {
    FakeEngine eng;
    eng.random().reseed(4);
    StationCollection sc;
    sc.addCaller(&eng, "W1AW");
    sc.addCaller(&eng, "K2ABC");
    sc.sweep();
    EXPECT_EQ(sc.size(), 2U);
}

TEST(StationCollection, ClearRemovesAll) {
    FakeEngine eng;
    StationCollection sc;
    sc.addQrn(&eng);
    sc.addQrn(&eng);
    sc.clear();
    EXPECT_TRUE(sc.empty());
}
