// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxStn.pas TDxStation. Each call into the simulation owns
// one of these — the audible "caller" trying to work the player. On
// construction we draw random Skills (1..3), Amplitude, Pitch, WPM,
// RST, NR, Qsb bandwidth, and an optional LID-flagged NR corruption
// from the distributions in DxStn.pas::CreateStation.
//
// Per-block side effect: GetBlock() applies the per-station Qsb
// (Rayleigh fading) on top of the base envelope. The Contest sums the
// resulting samples into its I/Q mix.

#pragma once

#include "dsp/Qsb.h"
#include "simulation/DxOperator.h"
#include "simulation/Station.h"

#include <memory>
#include <span>
#include <string>

namespace mr::sim {

class DxStation : public Station {
public:
    DxStation(Engine* engine, std::string heardCall);

    void processEvent(StationEvent event) override;

    std::size_t getBlock(std::span<float> out) override;

    [[nodiscard]] DxOperator& operatorState() noexcept { return *operator_; }
    [[nodiscard]] const DxOperator& operatorState() const noexcept { return *operator_; }

    // True when the operator has finished (Done or Failed). Contest's
    // garbage-collection loop frees these.
    [[nodiscard]] bool isFinished() const noexcept;

    // Pascal frees a DX station when its operator gives up (osFailed),
    // or when it is Done *and* its call matches the last logged QSO
    // (TDxStation.DataToLastQso ends with Free). A Done station that
    // never matches stays in the list, silent, until the next Run.
    [[nodiscard]] bool shouldRemove() const noexcept;
    void release() noexcept { released_ = true; }

private:
    std::unique_ptr<DxOperator> operator_;
    std::unique_ptr<mr::dsp::Qsb> qsb_;
    bool released_ = false;
};

}  // namespace mr::sim
