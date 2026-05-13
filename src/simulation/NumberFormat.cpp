// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/NumberFormat.h"

#include "core/Constants.h"
#include "core/Random.h"

#include <algorithm>
#include <cstdio>
#include <string>

namespace mr::sim {

namespace {

// In-place "replace all" on a std::string. The Pascal StringReplace
// with [rfReplaceAll] is functionally the same — we keep it inline so
// nrAsText reads like the Pascal source.
void replaceAll(std::string& s, std::string_view from, char to) {
    if (from.empty()) {
        return;
    }
    std::size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s[pos] = to;
        s.erase(pos + 1, from.size() - 1);
        ++pos;
    }
}

void replaceAll(std::string& s, std::string_view from, std::string_view to) {
    if (from.empty()) {
        return;
    }
    std::size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
}

}  // namespace

std::string nrAsText(const NrFormatOptions& opts, mr::core::Random& rng) {
    using namespace mr::constants::Sim;

    // Pascal: Format('%d%.3d', [RST, NR]). RST is 3 digits, NR is
    // padded to at least 3 digits.
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%d%.3d", opts.rst, opts.nr);
    std::string out(buf);

    // LID error injection: pick the rightmost digit in [2..7], bump it
    // up or down by 1, then append "EEEEE <correct nr>" so the receiver
    // hears the typo + correction. Done BEFORE the cut-number
    // substitutions so the substitutions apply to the corrupted form
    // too (matching Pascal Station.pas::NrAsText control flow).
    if (opts.lidError) {
        // Pascal: `Idx := Length(Result); if not (Result[Idx] in ['2'..'7']) then Dec(Idx)`.
        // Try last digit first; fall back to next-to-last.
        std::size_t idx = out.size();
        if (idx > 0 && (out[idx - 1] < '2' || out[idx - 1] > '7')) {
            --idx;
        }
        if (idx > 0 && out[idx - 1] >= '2' && out[idx - 1] <= '7') {
            const std::size_t target = idx - 1;
            if (rng.uniform01() < 0.5F) {
                --out[target];
            } else {
                ++out[target];
            }
            // Append correction tail with correct NR.
            char correct[16];
            std::snprintf(correct, sizeof(correct), "EEEEE %.3d", opts.nr);
            out += correct;
        }
    }

    // RST 599 → 5NN. Convention: in CW, the "9"s in RST are usually
    // sent as the abbreviated "N" because it's faster to key.
    replaceAll(out, std::string_view{"599"}, std::string_view{"5NN"});

    if (!opts.hstMode) {
        // Triple/double-zero collapses to TTT/TT first (otherwise the
        // per-digit '0' substitution below would chew them up wrong).
        replaceAll(out, std::string_view{"000"}, std::string_view{"TTT"});
        replaceAll(out, std::string_view{"00"}, std::string_view{"TT"});

        // Pascal: `if Random < 0.4 then '0' -> 'O' else if Random < 0.97
        // then '0' -> 'T'`. Two independent draws each time we encounter
        // the rule — but they're applied at most once each per call (the
        // original uses StringReplace with rfReplaceAll, which fires the
        // SAME substitution for every occurrence after a single random
        // draw decides which substitution to use).
        if (rng.uniform01() < kCutZeroAsO_Prob) {
            replaceAll(out, std::string_view{"0"}, 'O');
        } else if (rng.uniform01() < kCutZeroAsT_Prob) {
            replaceAll(out, std::string_view{"0"}, 'T');
        }

        if (rng.uniform01() < kCutNineAsN_Prob) {
            replaceAll(out, std::string_view{"9"}, 'N');
        }
    }

    return out;
}

}  // namespace mr::sim
