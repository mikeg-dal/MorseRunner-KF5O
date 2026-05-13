// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/StationCollection.h"

#include <algorithm>

namespace mr::sim {

DxStation* StationCollection::addCaller(Engine* engine, std::string callsign) {
    auto s = std::make_unique<DxStation>(engine, std::move(callsign));
    DxStation* raw = s.get();
    stations_.push_back(std::move(s));
    return raw;
}

QrnStation* StationCollection::addQrn(Engine* engine) {
    auto s = std::make_unique<QrnStation>(engine);
    QrnStation* raw = s.get();
    stations_.push_back(std::move(s));
    return raw;
}

QrmStation* StationCollection::addQrm(Engine* engine, std::string callsign) {
    auto s = std::make_unique<QrmStation>(engine, std::move(callsign));
    QrmStation* raw = s.get();
    stations_.push_back(std::move(s));
    return raw;
}

Station* StationCollection::take(std::unique_ptr<Station> s) {
    Station* raw = s.get();
    stations_.push_back(std::move(s));
    return raw;
}

void StationCollection::sweep() {
    // erase-remove idiom. Each subclass exposes its own isFinished()
    // — we dispatch via dynamic_cast since they don't share the
    // signature in the base class. This is fine performance-wise: the
    // sweep runs at most once per audio block (~21 Hz at default
    // buffer), and dx/qrn/qrm/my-station total counts stay under 50.
    auto it = std::remove_if(
        stations_.begin(), stations_.end(),
        [](const std::unique_ptr<Station>& s) -> bool {
            if (auto* dx = dynamic_cast<DxStation*>(s.get()); dx != nullptr) {
                return dx->isFinished();
            }
            if (auto* qrn = dynamic_cast<QrnStation*>(s.get()); qrn != nullptr) {
                return qrn->isFinished();
            }
            if (auto* qrm = dynamic_cast<QrmStation*>(s.get()); qrm != nullptr) {
                return qrm->isFinished();
            }
            return false;
        });
    stations_.erase(it, stations_.end());
}

std::size_t StationCollection::dxCount() const noexcept {
    std::size_t n = 0;
    for (const auto& s : stations_) {
        if (auto* dx = dynamic_cast<const DxStation*>(s.get()); dx != nullptr) {
            if (!dx->isFinished()) {
                ++n;
            }
        }
    }
    return n;
}

}  // namespace mr::sim
