// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/CallsignSource.h"

#include "core/Random.h"

#include <array>
#include <string>
#include <string_view>

namespace mr::sim {

namespace {

// Curated callsign prefixes drawn from common DX entities. Each entry
// is `(prefix, hasFixedDigit)` — if `hasFixedDigit` is true, the digit
// after the prefix is fixed; otherwise it's drawn from 0..9. This mix
// approximates the breadth a 17 000-call Master.dta provides without
// the parse overhead. Phase F replaces with the real database load.
struct PrefixEntry {
    std::string_view text;
    bool digitInPrefix;   // true when prefix already contains a digit
};

constexpr std::array<PrefixEntry, 62> kPrefixes = {{
    // North America — heavy US/Canada weighting matches contest activity
    {"K",    false}, {"N",    false}, {"W",    false}, {"AA",   false},
    {"AB",   false}, {"AC",   false}, {"AD",   false}, {"AE",   false},
    {"AF",   false}, {"AG",   false}, {"AI",   false}, {"AK",   false},
    {"KA",   false}, {"KB",   false}, {"KC",   false}, {"KE",   false},
    {"KF",   false}, {"KG",   false}, {"KK",   false}, {"NA",   false},
    {"NB",   false}, {"NC",   false}, {"NE",   false}, {"NF",   false},
    {"NN",   false}, {"WA",   false}, {"WB",   false}, {"WD",   false},
    {"WE",   false}, {"WF",   false}, {"WG",   false}, {"WW",   false},
    {"VE",   false}, {"VA",   false}, {"VY",   false},
    // Europe
    {"DL",   false}, {"DJ",   false}, {"DK",   false}, {"DF",   false},
    {"DG",   false}, {"DH",   false}, {"DM",   false}, {"G",    false},
    {"M",    false}, {"GM",   false}, {"GW",   false}, {"F",    false},
    {"EA",   false}, {"EI",   false}, {"I",    false}, {"OK",   false},
    {"OZ",   false}, {"SM",   false}, {"PA",   false}, {"ON",   false},
    // Asia / Pacific / South America
    {"JA",   false}, {"JE",   false}, {"BA",   false}, {"VK",   false},
    {"ZL",   false}, {"PY",   false}, {"LU",   false},
}};

// Common suffix patterns by length. Two-letter suffixes are the most
// frequent in real contest pile-ups; three-letter ones add variety.
constexpr char kLetters[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

[[nodiscard]] char randomLetter(mr::core::Random& rng) {
    return kLetters[rng.uniformInt(26)];
}

}  // namespace

std::string HardcodedCallsignSource::pickCall(mr::core::Random& rng) {
    const auto& p = kPrefixes[static_cast<std::size_t>(
        rng.uniformInt(static_cast<int>(kPrefixes.size())))];

    std::string out(p.text);
    if (!p.digitInPrefix) {
        out += static_cast<char>('0' + rng.uniformInt(10));
    }
    // 70% chance of 2-letter suffix, 30% chance of 3-letter (matches
    // real-world contest log distribution roughly).
    const int suffixLen = (rng.uniform01() < 0.7F) ? 2 : 3;
    for (int i = 0; i < suffixLen; ++i) {
        out += randomLetter(rng);
    }
    return out;
}

}  // namespace mr::sim
