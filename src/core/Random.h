// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of RndFunc.pas. Delphi's `Random` is a 32-bit LCG; we use
// std::mt19937 instead, which gives statistically equivalent results
// across the distributions the simulator cares about (uniform, normal,
// Rayleigh, Poisson, U-shaped). Bit-exact playback of a Delphi-captured
// run is intentionally NOT a goal — the golden-WAV test compares
// distributions, not samples.

#pragma once

#include <cstdint>
#include <random>

namespace mr::core {

class Random {
public:
    // Returns the process-wide instance. The Sim thread is the only hot
    // consumer; the GUI thread should not call this from paint paths.
    static Random& instance();

    // Seed accessors. `seed()` returns the actual seed used (logged at
    // startup for reproducibility); `reseed(s)` lets tests pin behavior.
    [[nodiscard]] std::uint64_t seed() const noexcept { return seed_; }
    void reseed(std::uint64_t s) noexcept;

    // Uniform on [0, 1). Equivalent to Delphi's `Random`.
    [[nodiscard]] float uniform01() noexcept;

    // Uniform integer in [0, n) — matches Delphi's `Random(n)` semantics.
    [[nodiscard]] int uniformInt(int n) noexcept;

    // Standard normal (Box-Muller) — port of RndFunc.pas RndNormal.
    [[nodiscard]] float normal() noexcept;

    // Gaussian with hard limits. Pascal:
    //     Result := Mean + RndNormal * 0.5 * Lim
    //     Result := clamp(Result, Mean ± Lim)
    [[nodiscard]] float gaussLim(float mean, float lim) noexcept;

    // Rayleigh distribution with given mean. Pascal: RndRayleigh =
    //     Mean * sqrt(-ln(Random) - ln(Random))
    [[nodiscard]] float rayleigh(float mean) noexcept;

    // Poisson(λ) via Knuth's product algorithm. Returns the number of
    // events; rarely exceeds 2λ for the activity values we use (1..9).
    [[nodiscard]] int poisson(float mean) noexcept;

    // U-shaped distribution on [-1, 1]. Pascal: RndUShaped =
    //     Sin(π * (Random - 0.5))
    // Peaks at ±1, troughs at 0 — used to give the DX-station amplitude
    // distribution a "rich man / poor man" character.
    [[nodiscard]] float uShaped() noexcept;

private:
    Random();

    std::mt19937 rng_;
    std::uint64_t seed_;

    // Cached second normal sample from a Box-Muller pair.
    bool hasSparedNormal_ = false;
    float sparedNormal_ = 0.0f;
};

}  // namespace mr::core
