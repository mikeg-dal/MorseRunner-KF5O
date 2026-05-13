// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pluggable callsign generator used by Contest to spawn DxStation and
// QrmStation instances. The real Master.dta-backed implementation
// lands in Phase F under Audio::CallsignDb; until then a small
// hardcoded list keeps Phase C testable and audible.
//
// HST mode wants `pickAndRemoveCall` so the same callsign never shows
// twice in a session; the simple stub treats it as a regular pick.

#pragma once

#include <string>

namespace mr::core { class Random; }

namespace mr::sim {

class CallsignSource {
public:
    virtual ~CallsignSource() = default;

    // Returns a random callsign for a fresh DX/QRM station.
    [[nodiscard]] virtual std::string pickCall(mr::core::Random& rng) = 0;

    // HST-only: consume the picked call so it never recurs in this
    // session. Default impl falls back to pickCall (matches the stub
    // hardcoded source's behavior).
    [[nodiscard]] virtual std::string pickAndRemoveCall(mr::core::Random& rng) {
        return pickCall(rng);
    }
};

// Phase-C stand-in: a small built-in list. Replaced by the Master.dta
// loader in Phase F.
class HardcodedCallsignSource : public CallsignSource {
public:
    [[nodiscard]] std::string pickCall(mr::core::Random& rng) override;
};

}  // namespace mr::sim
