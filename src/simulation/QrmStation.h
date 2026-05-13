// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of QrmStn.pas. A neighbouring station the player can hear but
// isn't part of the contest with. Sends one of QRL?, QRL? QRL?, long
// CQ, or QSY at construction, then on timeout re-keys a long CQ until
// its patience (1..5) runs out.
//
// Spawned by Contest at Dsp::kQrmSpawnPerBlockProb (0.0002) per block.

#pragma once

#include "simulation/Station.h"

#include <string>

namespace mr::sim {

class QrmStation : public Station {
public:
    // `randomCall` is the callsign drawn from the database (or fallback
    // "P29SX"); the QrmStation broadcasts using it as `<my>`. The
    // player's call is automatically used as `<his>` for the QSY
    // template.
    QrmStation(Engine* engine, std::string randomCall);

    void processEvent(StationEvent event) override;

    [[nodiscard]] bool isFinished() const noexcept { return finished_; }

private:
    int patience_ = 1;
    bool finished_ = false;
};

}  // namespace mr::sim
