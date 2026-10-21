// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/DxStation.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "simulation/Engine.h"

#include <cmath>

namespace mr::sim {

DxStation::DxStation(Engine* engine, std::string heardCall)
    : Station(engine),
      operator_(std::make_unique<DxOperator>(engine)),
      qsb_(std::make_unique<mr::dsp::Qsb>(engine->bufferSize(), engine->random())) {
    using namespace mr::constants::Sim;
    using namespace mr::constants::Dsp;

    auto& rng = engine_->random();

    // Pascal: HisCall := Ini.Call; MyCall := PickCall. From this
    // station's point of view "his" is the player and "my" is the DX
    // station's own call. CallsignDb integration in Group 3 supplies
    // the random pick; for now the caller passes the call in.
    setHisCall(std::string(engine_->myCallsign()));
    setMyCall(std::move(heardCall));

    // Pascal: Skills := 1 + Random(3) → uniform on [1..3].
    const int skills = 1 + rng.uniformInt(3);
    operator_->setSkills(skills);
    operator_->setCall(myCall_);
    operator_->setState(OperatorState::NeedPrevEnd);

    // Pascal: NrWithError := Ini.Lids and (Random < 0.1).
    nrWithError_ = engine_->lidsEnabled() && (rng.uniform01() < kLidNrErrorProb);

    setWpm(operator_->getWpm());
    setNr(operator_->getNumber());

    // Pascal: if Ini.Lids and (Random < 0.03) then RST := 559 + 10*Random(4); else 599.
    if (engine_->lidsEnabled() && rng.uniform01() < kLidRstErrorProb) {
        setRst(kLidRstBase + kLidRstStep * rng.uniformInt(kLidRstCount));
    } else {
        setRst(599);
    }

    // Pascal: Qsb.Bandwidth := 0.1 + Random/2; with 30% flutter chance,
    // bandwidth jumps to 3..33 Hz.
    float bw = kQsbBandwidthBase + rng.uniform01() * kQsbBandwidthSpread;
    if (engine_->flutterEnabled() && rng.uniform01() < kFlutterProb) {
        bw = kFlutterBwBase + rng.uniform01() * kFlutterBwSpread;
    }
    qsb_->setBandwidth(bw);

    // Pascal: Amplitude := 9000 + 18000 * (1 + RndUShaped).
    setAmplitude(kDxAmpBase + kDxAmpSpread * (1.0F + rng.uShaped()));

    // Pascal: Pitch := Round(RndGaussLim(0, 300)). Per-station BFO offset.
    setPitchHz(static_cast<int>(std::lround(rng.gaussLim(0.0F, kDxPitchSpreadHz))));

    // Pascal: TimeOut := NEVER; State := stCopying. The MeFinished event
    // will arrive on the next render tick.
    setTimeout(kNeverTimeout);
    state_ = StationState::Copying;
}

bool DxStation::isFinished() const noexcept {
    const auto s = operator_->state();
    return s == OperatorState::Done || s == OperatorState::Failed;
}

bool DxStation::shouldRemove() const noexcept {
    return released_ || operator_->state() == OperatorState::Failed;
}

void DxStation::processEvent(StationEvent event) {
    if (operator_->state() == OperatorState::Done) {
        return;
    }

    switch (event) {
        case StationEvent::MsgSent:
            // We finished sending and started listening. If the player
            // is already transmitting, wait for them to finish (their
            // evMeFinished drives us) instead of timing out over them.
            // Pascal: if Tst.Me.State = stSending then TimeOut := NEVER
            // else TimeOut := Oper.GetReplyTimeout.
            setTimeout((engine_ != nullptr && engine_->playerSending())
                           ? kNeverTimeout
                           : operator_->getReplyTimeoutBlocks());
            break;

        case StationEvent::Timeout: {
            if (state_ == StationState::Listening) {
                MessageSet noneSet;
                noneSet.set(static_cast<std::size_t>(Message::None));
                operator_->onMessageReceived(noneSet);
                if (operator_->state() == OperatorState::Failed) {
                    return;
                }
                state_ = StationState::PreparingToSend;
            }
            if (state_ == StationState::PreparingToSend) {
                for (int i = 0; i < operator_->repeatCount(); ++i) {
                    const Message reply = operator_->getReply();
                    if (reply != Message::None) {
                        sendMsg(reply);
                    }
                }
            }
            break;
        }

        case StationEvent::MeFinished: {
            if (state_ != StationState::Sending) {
                // Interpret the heard message. Pascal: if state in
                // [stCopying] then full FSM; in [stListening,
                // stPreparingToSend] only CQ/TU/NIL or msgGarbage.
                if (state_ == StationState::Copying) {
                    operator_->onMessageReceived(engine_->myLastMessage());
                } else {
                    const auto& heard = engine_->myLastMessage();
                    if (contains(heard, Message::Cq)
                        || contains(heard, Message::Tu)
                        || contains(heard, Message::Nil)) {
                        operator_->onMessageReceived(heard);
                    } else {
                        MessageSet garbageOnly;
                        garbageOnly.set(static_cast<std::size_t>(Message::Garbage));
                        operator_->onMessageReceived(garbageOnly);
                    }
                }
                if (operator_->state() == OperatorState::Failed) {
                    return;
                }
                setTimeout(operator_->getSendDelayBlocks());
                state_ = StationState::PreparingToSend;
            }
            break;
        }

        case StationEvent::MeStarted:
            // Player started transmitting again — switch to copy mode.
            if (state_ != StationState::Sending) {
                state_ = StationState::Copying;
            }
            setTimeout(kNeverTimeout);
            break;
    }
}

std::size_t DxStation::getBlock(std::span<float> out) {
    const std::size_t written = Station::getBlock(out);
    // Pascal: TDxStation.GetBlock invokes Qsb.ApplyTo if Ini.Qsb.
    // We honor the engine's qsb flag.
    if (written > 0 && engine_ != nullptr && engine_->qsbEnabled()) {
        qsb_->applyTo(std::span<float>(out.data(), written));
    }
    return written;
}

}  // namespace mr::sim
