// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxOper.pas TDxOperator. The QSO state machine the DX
// stations follow — encodes the dance "did the operator hear me / did
// I copy his number / should I send my call again" in a flat enum.
//
// State diagram (Pascal symbols mirrored, prefixed with "Need" so the
// reader sees what the operator is waiting for next):
//
//   NeedPrevEnd → NeedQso → NeedNr ┐
//                                  ├→ NeedCall ──┐
//                                  └→ NeedCallNr ┘
//                                                ↓
//                                             NeedEnd → Done
//
//   (Any state) → Failed   on patience exhaustion or contradiction
//
// Patience is decremented on every received message that doesn't
// advance the operator; reaching zero forces Failed. Entering NeedQso
// uses a Rayleigh-distributed patience with mean 4; other states use
// the constant kFullPatience (5).

#pragma once

#include "simulation/IsMyCall.h"
#include "simulation/Messages.h"

#include <string>
#include <string_view>

namespace mr::sim {

class Engine;

enum class OperatorState {
    NeedPrevEnd,
    NeedQso,
    NeedNr,
    NeedCall,
    NeedCallNr,
    NeedEnd,
    Done,
    Failed,
};

class DxOperator {
public:
    explicit DxOperator(Engine* engine);

    // The DX's own callsign — the operator checks heard calls against
    // this on every msgHisCall arrival.
    void setCall(std::string call) { call_ = std::move(call); }
    [[nodiscard]] const std::string& call() const noexcept { return call_; }

    // Operator skill level 1..3. Sets baseline reply delay, reply
    // timeout, NR growth rate. Drawn from 1+Random(3) in TDxStation.
    void setSkills(int skills) noexcept { skills_ = skills; }
    [[nodiscard]] int skills() const noexcept { return skills_; }

    [[nodiscard]] OperatorState state() const noexcept { return state_; }
    [[nodiscard]] int patience() const noexcept { return patience_; }
    [[nodiscard]] int repeatCount() const noexcept { return repeatCnt_; }

    // Force the operator into a particular state. Pascal: SetState.
    // Also recomputes patience and repeatCount according to the state.
    void setState(OperatorState newState);

    // Wpm / NR / timing — match the formulas in DxOper.pas.
    // Used by TDxStation when constructing the audible station and
    // again whenever a fresh number is needed.
    [[nodiscard]] int getWpm();
    [[nodiscard]] int getNumber();
    [[nodiscard]] int getSendDelayBlocks();
    [[nodiscard]] int getReplyTimeoutBlocks();

    // Process a received message-set from the player's transmission.
    // Updates state and patience. Pascal: TDxOperator.MsgReceived.
    void onMessageReceived(const MessageSet& heard);

    // Selects the operator's next reply based on the current state.
    // Pascal: TDxOperator.GetReply. Returns Message::None when no
    // reply is appropriate (e.g. state == Done or Failed).
    [[nodiscard]] Message getReply();

private:
    void decrementPatience();
    [[nodiscard]] CallMatch checkHeardCall();

    Engine* engine_;
    std::string call_;
    int skills_ = 1;
    int patience_ = 0;
    int repeatCnt_ = 1;
    OperatorState state_ = OperatorState::NeedPrevEnd;
};

}  // namespace mr::sim
