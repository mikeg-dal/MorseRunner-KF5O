// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Minimal abstract interface that the Station hierarchy and DxOperator
// consult for shared simulation state. The original Delphi
// implementation reaches into the global `Tst` (TContest singleton)
// from anywhere — convenient but untestable. We replace that with a
// pointer to this interface, injected at station construction.
//
// Group 2 ports Station / DxStation / DxOperator and uses this
// interface only. Group 4's Sim::Contest is the real implementation;
// the unit tests for Group 2 use a small fake.

#pragma once

#include "simulation/Messages.h"

#include <string>
#include <string_view>

namespace mr::core { class Random; }

namespace mr::sim {

enum class RunMode {
    Stop,
    PileUp,
    Single,
    Wpx,
    Hst,
};

class Engine {
public:
    virtual ~Engine() = default;

    // Time/pacing.
    [[nodiscard]] virtual int currentBlockIndex() const noexcept = 0;
    [[nodiscard]] virtual float currentMinute() const noexcept = 0;

    // What the player station is doing.
    [[nodiscard]] virtual std::string_view myCallsign() const = 0;
    // The callsign the player most recently keyed (their `HisCall`,
    // i.e. what they think the DX called).
    [[nodiscard]] virtual std::string_view heardCallsign() const = 0;
    // The message set the player station most recently sent. DxOperator
    // inspects this to decide how to respond.
    [[nodiscard]] virtual const MessageSet& myLastMessage() const = 0;

    // Run-mode dispatch.
    [[nodiscard]] virtual RunMode runMode() const noexcept = 0;

    // Global feature toggles, mirrored from the Ini layer.
    [[nodiscard]] virtual bool lidsEnabled() const noexcept = 0;
    [[nodiscard]] virtual bool flutterEnabled() const noexcept = 0;
    [[nodiscard]] virtual bool qsbEnabled() const noexcept = 0;

    // Settings used by station construction.
    [[nodiscard]] virtual int targetWpm() const noexcept = 0;
    [[nodiscard]] virtual int activity() const noexcept = 0;
    [[nodiscard]] virtual int bufferSize() const noexcept = 0;

    // Shared random number source. Stations and the FSM all draw from
    // the same instance so reseeding deterministically reproduces runs.
    [[nodiscard]] virtual mr::core::Random& random() = 0;
};

}  // namespace mr::sim
