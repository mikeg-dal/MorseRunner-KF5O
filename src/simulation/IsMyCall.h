// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxOper.pas::IsMyCall. Decides whether a callsign heard over
// the air ("his" — what the player thinks they typed) matches the DX
// station's actual call ("my"). The match runs a dynamic-programming
// Levenshtein-style edit-distance with three twists:
//
//  1. `?` characters in the heard call act as wildcards that match any
//     single character (or, at the trailing edge, zero characters).
//  2. The end of the heard call may be missing — a heard "K1A" against
//     own call "K1ABC" doesn't penalize the dropped "BC".
//  3. Edit costs are uniform (W_X = W_Y = W_D = 2). A total penalty of
//     0 means Yes; 1 or 2 means Almost (a partial / near-miss); >2 is
//     No. Several post-classification adjustments handle special cases
//     for short calls and LID-station mishearing.

#pragma once

#include <string_view>

namespace mr::core { class Random; }

namespace mr::sim {

enum class CallMatch {
    No,
    Almost,
    Yes,
};

struct IsMyCallOptions {
    // The DX station's true callsign (what the FSM is verifying against).
    std::string_view mine;
    // What the player keyed (or what we received). May contain '?' as a
    // wildcard for unsure characters.
    std::string_view his;
    // When true, the simulation is configured to model LID operators
    // (poor copy / sloppy keying). This flips a small probability of
    // mishearing Yes↔Almost. When false, the function also tightens
    // the rule for length-2 heard calls (no Almost downgrade).
    bool lidsMode = false;
};

// Pure function — but depends on a Random for the LID mishearing
// coin flip. Pass the process-wide Random by reference.
[[nodiscard]] CallMatch isMyCall(const IsMyCallOptions& opts, mr::core::Random& rng);

}  // namespace mr::sim
