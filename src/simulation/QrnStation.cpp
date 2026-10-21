// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/QrnStation.h"

#include "core/Constants.h"
#include "core/DelphiRound.h"
#include "core/Random.h"
#include "simulation/Engine.h"

#include <cmath>

namespace mr::sim {

QrnStation::QrnStation(Engine* engine) : Station(engine) {
    using namespace mr::constants::Audio;
    using namespace mr::constants::Dsp;

    auto& rng = engine_->random();
    const int bufSize = engine_->bufferSize();

    // Pascal: Dur := SecondsToBlocks(Random) * Ini.BufSize.
    // The total envelope length spans up to ~1 second of audio, but
    // most of those samples will stay 0 — only ~1% receive a spike.
    const double seconds = static_cast<double>(rng.uniform01());
    const int blocks = mr::core::delphiRound(
        seconds * static_cast<double>(kSampleRate) / static_cast<double>(bufSize));
    const std::size_t durSamples =
        static_cast<std::size_t>(blocks) * static_cast<std::size_t>(bufSize);

    envelope_.assign(durSamples, 0.0F);

    // Pascal: Amplitude := 1E5 * Power(10, 2*Random) — uniformly
    // distributed in log10 from 1E5 (60 dB above the noise floor) to
    // 1E7 (the AGC will clamp the loudest bursts).
    setAmplitude(kQrnBurstAmpBase
                 * std::pow(10.0F, 2.0F * rng.uniform01()));

    // Pascal: per-sample 1% chance of (Random-0.5)*Amplitude. The
    // sparse spikes are what give QRN its characteristic crackle.
    for (float& s : envelope_) {
        if (rng.uniform01() < kQrnBurstEnvelopeSpikeProb) {
            s = (rng.uniform01() - 0.5F) * amplitude_;
        }
    }

    state_ = StationState::Sending;
}

void QrnStation::processEvent(StationEvent event) {
    // Pascal: if AEvent = evMsgSent then Free. We don't `delete this` —
    // ownership is held by StationCollection; we just flag ourselves
    // for sweep on the next GC pass.
    if (event == StationEvent::MsgSent) {
        finished_ = true;
    }
}

}  // namespace mr::sim
