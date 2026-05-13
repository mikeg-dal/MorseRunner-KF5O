// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/QrmStation.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "simulation/Engine.h"

#include <cmath>

namespace mr::sim {

namespace {

// Pascal: SecondsToBlocks(4) gives the baseline reload interval before
// the QrmStation re-keys a long CQ.
constexpr float kQrmReloadSeconds = 4.0F;
constexpr float kQrmReloadJitter = 2.0F;

int secondsToBlocks(float seconds, int bufSize) {
    using mr::constants::Audio::kSampleRate;
    return static_cast<int>(std::lround(
        static_cast<double>(seconds) * static_cast<double>(kSampleRate)
        / static_cast<double>(bufSize)));
}

}  // namespace

QrmStation::QrmStation(Engine* engine, std::string randomCall)
    : Station(engine) {
    using namespace mr::constants::Dsp;

    auto& rng = engine_->random();

    // Pascal: Patience := 1 + Random(5). Bursty interferer that
    // recycles 1..5 times before going silent.
    patience_ = 1 + rng.uniformInt(5);

    setMyCall(std::move(randomCall));
    setHisCall(std::string(engine_->myCallsign()));

    // Pascal: Amplitude := 5000 + 25000 * Random.
    setAmplitude(kQrmAmpBase + kQrmAmpRange * rng.uniform01());

    // Pascal: Pitch := Round(RndGaussLim(0, 300)).
    setPitchHz(static_cast<int>(std::lround(rng.gaussLim(0.0F, kQrmPitchSpreadHz))));

    // Pascal: Wpm := 30 + Random(20). Sloppy hand-keyer speed range.
    setWpm(kQrmWpmBase + rng.uniformInt(kQrmWpmRange));

    // Pascal: case Random(7) of ...
    const int roll = rng.uniformInt(7);
    switch (roll) {
        case 0:                 sendMsg(Message::Qrl); break;
        case 1: case 2:         sendMsg(Message::Qrl2); break;
        case 3: case 4: case 5: sendMsg(Message::LongCq); break;
        case 6:                 sendMsg(Message::Qsy); break;
        default:                sendMsg(Message::LongCq); break;
    }
}

void QrmStation::processEvent(StationEvent event) {
    auto& rng = engine_->random();
    const int bufSize = engine_->bufferSize();

    switch (event) {
        case StationEvent::MsgSent: {
            --patience_;
            if (patience_ <= 0) {
                finished_ = true;
                return;
            }
            // Pascal: Timeout := Round(RndGaussLim(SecondsToBlocks(4), 2)).
            const int base = secondsToBlocks(kQrmReloadSeconds, bufSize);
            setTimeout(static_cast<int>(std::lround(
                rng.gaussLim(static_cast<float>(base), kQrmReloadJitter))));
            break;
        }
        case StationEvent::Timeout:
            sendMsg(Message::LongCq);
            break;
        case StationEvent::MeStarted:
        case StationEvent::MeFinished:
            // QrmStations ignore player activity — they're not part of
            // the QSO. Pascal omits these arms entirely.
            break;
    }
}

}  // namespace mr::sim
