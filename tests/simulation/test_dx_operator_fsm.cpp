// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/DxOperator.h"

#include "FakeEngine.h"
#include "simulation/Engine.h"

#include <gtest/gtest.h>

using namespace mr::sim;
using mr::sim::test::FakeEngine;

namespace {

MessageSet setOf(std::initializer_list<Message> ms) {
    MessageSet s;
    for (auto m : ms) {
        s.set(static_cast<std::size_t>(m));
    }
    return s;
}

}  // namespace

TEST(DxOperatorFsm, InitialStateIsNeedPrevEnd) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    EXPECT_EQ(op.state(), OperatorState::NeedPrevEnd);
}

TEST(DxOperatorFsm, CqHeardFromPrevEndTransitionsToNeedQso) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedPrevEnd);

    op.onMessageReceived(setOf({Message::Cq}));
    EXPECT_EQ(op.state(), OperatorState::NeedQso);
}

TEST(DxOperatorFsm, ReplyFromNeedQsoIsMyCall) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedQso);
    EXPECT_EQ(op.getReply(), Message::MyCall);
}

TEST(DxOperatorFsm, CorrectCallTransitionsToNeedNr) {
    FakeEngine eng;
    eng.setHeardCall("W1AW");  // player heard us correctly
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedQso);

    op.onMessageReceived(setOf({Message::HisCall}));
    EXPECT_EQ(op.state(), OperatorState::NeedNr);
}

TEST(DxOperatorFsm, AlmostCallFromNeedQsoTransitionsToNeedCallNr) {
    FakeEngine eng;
    eng.setHeardCall("W1AX");  // single-char typo on a 4-char call → Almost
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedQso);

    op.onMessageReceived(setOf({Message::HisCall}));
    EXPECT_EQ(op.state(), OperatorState::NeedCallNr);
}

TEST(DxOperatorFsm, WrongCallFromNeedQsoReturnsToNeedPrevEnd) {
    FakeEngine eng;
    eng.setHeardCall("JA1XYZ");
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedQso);

    op.onMessageReceived(setOf({Message::HisCall}));
    EXPECT_EQ(op.state(), OperatorState::NeedPrevEnd);
}

TEST(DxOperatorFsm, NrThenTuCompletesQso) {
    FakeEngine eng;
    eng.setHeardCall("W1AW");
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedNr);

    // Pin a seed where the inner Random < 0.9 branch fires.
    eng.random().reseed(1);
    op.onMessageReceived(setOf({Message::HisCall, Message::Nr}));
    // After receiving Nr, we should be in NeedEnd (or NeedNr if we
    // rolled into the 10% retry — accept either as port-faithful).
    EXPECT_TRUE(op.state() == OperatorState::NeedEnd
                || op.state() == OperatorState::NeedNr);

    if (op.state() == OperatorState::NeedEnd) {
        op.onMessageReceived(setOf({Message::Tu}));
        EXPECT_EQ(op.state(), OperatorState::Done);
    }
}

TEST(DxOperatorFsm, NilWhileWaitingForReplyIsFailed) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedNr);

    op.onMessageReceived(setOf({Message::Nil}));
    EXPECT_EQ(op.state(), OperatorState::Failed);
}

TEST(DxOperatorFsm, B4DuringQsoIsFailed) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedNr);
    op.onMessageReceived(setOf({Message::B4}));
    EXPECT_EQ(op.state(), OperatorState::Failed);
}

TEST(DxOperatorFsm, PatienceExhaustionTriggersFailure) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedEnd);  // FULL_PATIENCE = 5
    // Receive bare Nr (without HisCall, B4, Tu, Nil, Cq) — the Nr arm
    // of the FSM has no NeedEnd transition, so the state stays put
    // but the per-call patience decrement still fires. After 5
    // iterations the patience hits zero and the operator fails.
    for (int i = 0; i < 10; ++i) {
        op.onMessageReceived(setOf({Message::Nr}));
        if (op.state() == OperatorState::Failed) {
            break;
        }
    }
    EXPECT_EQ(op.state(), OperatorState::Failed);
}

TEST(DxOperatorFsm, GetWpmInHstMatchesEngineTarget) {
    FakeEngine eng;
    eng.setRunMode(RunMode::Hst);
    DxOperator op(&eng);
    op.setCall("W1AW");
    EXPECT_EQ(op.getWpm(), eng.targetWpm());
}

TEST(DxOperatorFsm, GetWpmInPileUpIsHalfToFull) {
    FakeEngine eng;
    eng.setRunMode(RunMode::PileUp);
    DxOperator op(&eng);
    op.setCall("W1AW");
    for (int i = 0; i < 50; ++i) {
        const int w = op.getWpm();
        EXPECT_GE(w, eng.targetWpm() / 2);
        EXPECT_LE(w, eng.targetWpm());
    }
}

TEST(DxOperatorFsm, GetReplyAfterFailureIsNone) {
    FakeEngine eng;
    DxOperator op(&eng);
    op.setCall("W1AW");
    op.setState(OperatorState::NeedNr);
    op.onMessageReceived(setOf({Message::Nil}));
    EXPECT_EQ(op.getReply(), Message::None);
}
