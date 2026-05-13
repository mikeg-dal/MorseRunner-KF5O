// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of QrnStn.pas. Atmospheric noise burst — a one-shot station
// that emits a sparse impulse train into the Contest's I/Q mix, then
// frees itself. Spawned by Contest at Dsp::kQrnBurstPerBlockProb (1%)
// per audio block.

#pragma once

#include "simulation/Station.h"

namespace mr::sim {

class QrnStation : public Station {
public:
    explicit QrnStation(Engine* engine);

    void processEvent(StationEvent event) override;

    // True once the burst's envelope has been fully consumed — the
    // StationCollection sweeps these on the next GC pass.
    [[nodiscard]] bool isFinished() const noexcept { return finished_; }

private:
    bool finished_ = false;
};

}  // namespace mr::sim
