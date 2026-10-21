// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of StnColl.pas TStations. Owns every live audible source (DX
// callers + QRN/QRM interferers). Provides factory methods that mirror
// the Pascal AddCaller / AddQrn / AddQrm helpers and a sweep() pass
// for garbage-collecting finished stations.

#pragma once

#include "simulation/DxStation.h"
#include "simulation/QrmStation.h"
#include "simulation/QrnStation.h"
#include "simulation/Station.h"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace mr::sim {

class StationCollection {
public:
    using Container = std::vector<std::unique_ptr<Station>>;

    StationCollection() = default;

    // Factories. Pascal: AddCaller / AddQrn / AddQrm. The returned
    // pointer is a borrowed reference — ownership stays with the
    // collection. The pointer is invalidated only when the station is
    // swept (see sweep()).
    DxStation* addCaller(Engine* engine, std::string callsign);
    QrnStation* addQrn(Engine* engine);
    QrmStation* addQrm(Engine* engine, std::string callsign);

    // Direct adoption — used by tests and by the Contest engine when
    // it builds a Station out of band (e.g. the player station).
    Station* take(std::unique_ptr<Station> s);

    // Removes finished stations: DxStation::shouldRemove(), or
    // isFinished() for QRN / QRM. Stable order; reuses vector capacity.
    void sweep();

    // Iteration helpers — the Contest's per-block render loop needs
    // both indexed access and reverse iteration (for processing
    // events while permitting mid-iteration removal).
    [[nodiscard]] std::size_t size() const noexcept { return stations_.size(); }
    [[nodiscard]] bool empty() const noexcept { return stations_.empty(); }
    [[nodiscard]] Station& operator[](std::size_t i) noexcept { return *stations_[i]; }
    [[nodiscard]] const Station& operator[](std::size_t i) const noexcept {
        return *stations_[i];
    }

    [[nodiscard]] auto begin() noexcept { return stations_.begin(); }
    [[nodiscard]] auto end() noexcept { return stations_.end(); }
    [[nodiscard]] auto begin() const noexcept { return stations_.begin(); }
    [[nodiscard]] auto end() const noexcept { return stations_.end(); }

    void clear() noexcept { stations_.clear(); }

    // How many DxStations are alive (i.e. not finished)? Pascal:
    // TContest.DxCount. Used by Single / HST run modes to top up
    // callers.
    [[nodiscard]] std::size_t dxCount() const noexcept;

private:
    Container stations_;
};

}  // namespace mr::sim
