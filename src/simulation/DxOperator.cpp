// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/DxOperator.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "simulation/Engine.h"
#include "simulation/IsMyCall.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace mr::sim {

namespace {

// Pascal: SecondsToBlocks = Round(DEFAULTRATE / BufSize * Sec).
[[nodiscard]] int secondsToBlocks(float seconds) {
    using mr::constants::Audio::kDefaultBufferSamples;
    using mr::constants::Audio::kSampleRate;
    return static_cast<int>(std::lround(
        static_cast<double>(seconds) * static_cast<double>(kSampleRate)
        / static_cast<double>(kDefaultBufferSamples)));
}

}  // namespace

DxOperator::DxOperator(Engine* engine) : engine_(engine) {
    setState(OperatorState::NeedPrevEnd);
}

void DxOperator::setState(OperatorState newState) {
    using namespace mr::constants::Sim;
    state_ = newState;
    if (newState == OperatorState::NeedQso) {
        // Pascal: Patience := Round(RndRayleigh(4)).
        patience_ = static_cast<int>(
            std::lround(engine_->random().rayleigh(kNeedQsoPatienceMean)));
    } else {
        patience_ = kFullPatience;
    }
    // Repeat count: 10% chance of 2 only when entering NeedQso and not
    // in Single / HST modes. Pascal: TDxOperator.SetState.
    repeatCnt_ = 1;
    if (newState == OperatorState::NeedQso) {
        const RunMode mode = engine_->runMode();
        if (mode != RunMode::Single && mode != RunMode::Hst
            && engine_->random().uniform01() < kRepeatProb) {
            repeatCnt_ = kRepeatCount;
        }
    }
}

int DxOperator::getWpm() {
    if (engine_->runMode() == RunMode::Hst) {
        return engine_->targetWpm();
    }
    // Pascal: round(Wpm * 0.5 * (1 + Random)) — uniformly distributed
    // 50%..100% of the player's WPM.
    const double w = static_cast<double>(engine_->targetWpm())
                     * 0.5
                     * (1.0 + static_cast<double>(engine_->random().uniform01()));
    return static_cast<int>(std::lround(w));
}

int DxOperator::getNumber() {
    // Pascal: 1 + Round(Random * Tst.Minute * Skills). Numbers grow
    // through the contest hour and faster for higher-skill operators.
    const double n = static_cast<double>(engine_->random().uniform01())
                     * static_cast<double>(engine_->currentMinute())
                     * static_cast<double>(skills_);
    return 1 + static_cast<int>(std::lround(n));
}

int DxOperator::getSendDelayBlocks() {
    if (state_ == OperatorState::NeedPrevEnd) {
        // Don't reply yet; wait for the player to finish a QSO.
        // Pascal returns the literal NEVER (MAXINT).
        return std::numeric_limits<int>::max();
    }
    if (engine_->runMode() == RunMode::Hst) {
        // HST: tighter pacing, scaled by WPM.
        return secondsToBlocks(
            0.05F + 0.5F * engine_->random().uniform01() * 10.0F
                        / static_cast<float>(engine_->targetWpm()));
    }
    // Non-HST: 100 ms .. 600 ms.
    return secondsToBlocks(0.1F + 0.5F * engine_->random().uniform01());
}

int DxOperator::getReplyTimeoutBlocks() {
    int blocks;
    if (engine_->runMode() == RunMode::Hst) {
        // Pascal: SecondsToBlocks(60 / Wpm).
        blocks = secondsToBlocks(60.0F / static_cast<float>(engine_->targetWpm()));
    } else {
        // Pascal: SecondsToBlocks(6 - Skills). Skills 1→5s, 2→4s, 3→3s.
        blocks = secondsToBlocks(static_cast<float>(6 - skills_));
    }
    // Pascal: Round(RndGaussLim(Result, Result/2)). Gaussian ±50%.
    const float jittered =
        engine_->random().gaussLim(static_cast<float>(blocks),
                                   static_cast<float>(blocks) / 2.0F);
    return std::max(1, static_cast<int>(std::lround(jittered)));
}

void DxOperator::decrementPatience() {
    if (state_ == OperatorState::Done) {
        return;
    }
    --patience_;
    if (patience_ < 1) {
        state_ = OperatorState::Failed;
    }
}

CallMatch DxOperator::checkHeardCall() {
    IsMyCallOptions opts;
    opts.mine = call_;
    opts.his = engine_->heardCallsign();
    opts.lidsMode = engine_->lidsEnabled();
    return isMyCall(opts, engine_->random());
}

void DxOperator::onMessageReceived(const MessageSet& heard) {
    // Pascal early-outs: msgCq and msgNil both short-circuit through
    // dedicated arms before falling through to the per-message logic.
    if (contains(heard, Message::Cq)) {
        switch (state_) {
            case OperatorState::NeedPrevEnd: setState(OperatorState::NeedQso); break;
            case OperatorState::NeedQso:     decrementPatience(); break;
            case OperatorState::NeedNr:
            case OperatorState::NeedCall:
            case OperatorState::NeedCallNr:  state_ = OperatorState::Failed; break;
            case OperatorState::NeedEnd:     state_ = OperatorState::Done; break;
            default: break;
        }
        return;
    }
    if (contains(heard, Message::Nil)) {
        switch (state_) {
            case OperatorState::NeedPrevEnd: setState(OperatorState::NeedQso); break;
            case OperatorState::NeedQso:     decrementPatience(); break;
            case OperatorState::NeedNr:
            case OperatorState::NeedCall:
            case OperatorState::NeedCallNr:
            case OperatorState::NeedEnd:     state_ = OperatorState::Failed; break;
            default: break;
        }
        return;
    }

    // msgHisCall: classify the heard call and branch by quality.
    if (contains(heard, Message::HisCall)) {
        switch (checkHeardCall()) {
            case CallMatch::Yes:
                if (state_ == OperatorState::NeedPrevEnd
                    || state_ == OperatorState::NeedQso) {
                    setState(OperatorState::NeedNr);
                } else if (state_ == OperatorState::NeedCallNr) {
                    setState(OperatorState::NeedNr);
                } else if (state_ == OperatorState::NeedCall) {
                    setState(OperatorState::NeedEnd);
                }
                break;
            case CallMatch::Almost:
                if (state_ == OperatorState::NeedPrevEnd
                    || state_ == OperatorState::NeedQso) {
                    setState(OperatorState::NeedCallNr);
                } else if (state_ == OperatorState::NeedNr) {
                    setState(OperatorState::NeedCallNr);
                } else if (state_ == OperatorState::NeedEnd) {
                    setState(OperatorState::NeedCall);
                }
                break;
            case CallMatch::No:
                if (state_ == OperatorState::NeedQso) {
                    state_ = OperatorState::NeedPrevEnd;
                } else if (state_ == OperatorState::NeedNr
                           || state_ == OperatorState::NeedCall
                           || state_ == OperatorState::NeedCallNr) {
                    state_ = OperatorState::Failed;
                } else if (state_ == OperatorState::NeedEnd) {
                    state_ = OperatorState::Done;
                }
                break;
        }
    }

    if (contains(heard, Message::B4)) {
        switch (state_) {
            case OperatorState::NeedPrevEnd:
            case OperatorState::NeedQso:    setState(OperatorState::NeedQso); break;
            case OperatorState::NeedNr:
            case OperatorState::NeedEnd:    state_ = OperatorState::Failed; break;
            case OperatorState::NeedCall:
            case OperatorState::NeedCallNr: break;  // allow call correction
            default: break;
        }
    }

    if (contains(heard, Message::Nr)) {
        using namespace mr::constants::Sim;
        const bool inHst = (engine_->runMode() == RunMode::Hst);
        const float roll = engine_->random().uniform01();
        switch (state_) {
            case OperatorState::NeedPrevEnd: break;
            case OperatorState::NeedQso:     state_ = OperatorState::NeedPrevEnd; break;
            case OperatorState::NeedNr:
                if (roll < 0.9F || inHst) {
                    setState(OperatorState::NeedEnd);
                }
                break;
            case OperatorState::NeedCallNr:
                if (roll < 0.9F || inHst) {
                    setState(OperatorState::NeedCall);
                }
                break;
            default: break;
        }
    }

    if (contains(heard, Message::Tu)) {
        switch (state_) {
            case OperatorState::NeedPrevEnd: setState(OperatorState::NeedQso); break;
            case OperatorState::NeedEnd:     state_ = OperatorState::Done; break;
            default: break;  // TU ignored mid-QSO
        }
    }

    // Pascal: `if (not Lids) and (AMsg = [msgGarbage]) then State :=
    //          osNeedPrevEnd`. Reset after pure interference.
    if (!engine_->lidsEnabled()) {
        // AMsg = [msgGarbage] means the set has exactly one element,
        // which is Garbage. We check membership and absence of others.
        if (contains(heard, Message::Garbage)
            && heard.count() == 1) {
            state_ = OperatorState::NeedPrevEnd;
        }
    }

    // Pascal final line: any non-NeedPrevEnd state pays a patience cost.
    if (state_ != OperatorState::NeedPrevEnd) {
        decrementPatience();
    }
}

Message DxOperator::getReply() {
    using namespace mr::constants::Sim;
    const bool inHst = (engine_->runMode() == RunMode::Hst);

    switch (state_) {
        case OperatorState::NeedPrevEnd:
        case OperatorState::Done:
        case OperatorState::Failed:
            return Message::None;

        case OperatorState::NeedQso:
            return Message::MyCall;

        case OperatorState::NeedNr:
            // Pascal: ask for the NR after first attempt; otherwise AGN.
            if (patience_ == kFullPatience - 1
                || engine_->random().uniform01() < 0.3F) {
                return Message::NrQm;
            }
            return Message::Agn;

        case OperatorState::NeedCall:
            if (inHst || engine_->random().uniform01() > 0.5F) {
                return Message::DeMyCallNr1;
            }
            if (engine_->random().uniform01() > 0.25F) {
                return Message::DeMyCallNr2;
            }
            return Message::MyCallNr2;

        case OperatorState::NeedCallNr:
            if (inHst || engine_->random().uniform01() > 0.5F) {
                return Message::DeMyCall1;
            }
            return Message::DeMyCall2;

        case OperatorState::NeedEnd:
            if (patience_ < kFullPatience - 1) {
                return Message::Nr;
            }
            if (inHst || engine_->random().uniform01() < 0.9F) {
                return Message::R_Nr;
            }
            return Message::R_Nr2;
    }
    return Message::None;
}

}  // namespace mr::sim
