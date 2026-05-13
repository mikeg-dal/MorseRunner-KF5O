// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/IsMyCall.h"

#include "core/Constants.h"
#include "core/Random.h"

#include <algorithm>
#include <cstddef>
#include <vector>

namespace mr::sim {

namespace {

[[nodiscard]] std::size_t countNonWildcards(std::string_view s) noexcept {
    std::size_t n = 0;
    for (const char c : s) {
        if (c != '?') {
            ++n;
        }
    }
    return n;
}

}  // namespace

CallMatch isMyCall(const IsMyCallOptions& opts, mr::core::Random& rng) {
    using namespace mr::constants::Sim;

    const std::string_view mine = opts.mine;
    const std::string_view his = opts.his;

    // DP matrix `M` is (|his|+1) × (|mine|+1). M[x][y] is the minimum
    // edit cost transforming `his[0..x)` into a prefix of `mine[0..y)`.
    // Pascal indexing is 1-based; we shift to 0-based, but keep the
    // same recurrence shape so the rule logic is easy to compare.
    const std::size_t H = his.size();
    const std::size_t M_ = mine.size();

    std::vector<std::vector<int>> matrix(H + 1, std::vector<int>(M_ + 1, 0));

    // Pascal: M[x,0] := M[x-1,0] + W_X (insertion cost). M[0,y] = 0
    // (free skips on `mine` — modeling "the trailing letters of mine
    // might not have been keyed yet, so we don't penalize them").
    for (std::size_t x = 1; x <= H; ++x) {
        matrix[x][0] = matrix[x - 1][0] + kLevInsCost;
    }

    for (std::size_t x = 1; x <= H; ++x) {
        for (std::size_t y = 1; y <= M_; ++y) {
            const char c = his[x - 1];   // heard character (may be '?')
            const char c0 = mine[y - 1]; // true character

            // Pascal: T := M[x, y-1]; if (x < High) and (C[x] <> '?') then Inc(T, W_Y);
            // Skip a char on `mine` — free at the trailing edge (x == H)
            // OR when the heard char is a wildcard that "ate" this slot.
            int T = matrix[x][y - 1];
            if (x < H && c != '?') {
                T += kLevDelCost;
            }

            // Pascal: L := M[x-1, y]; if (C[x] <> '?') then Inc(L, W_X).
            int L = matrix[x - 1][y];
            if (c != '?') {
                L += kLevInsCost;
            }

            // Pascal: D := M[x-1, y-1]; if not (C[x] in [C0[y], '?']) then Inc(D, W_D).
            int D = matrix[x - 1][y - 1];
            if (c != '?' && c != c0) {
                D += kLevSubstCost;
            }

            matrix[x][y] = std::min({T, D, L});
        }
    }

    const int penalty = matrix[H][M_];

    CallMatch result;
    if (penalty == 0) {
        result = CallMatch::Yes;
    } else if (penalty <= kLevMatchThresh) {
        result = CallMatch::Almost;
    } else {
        result = CallMatch::No;
    }

    // Pascal post-classification corrections:

    // 1) If LIDs are off and the heard string is exactly 2 chars, an
    //    Almost is upgraded back to No — a two-character partial is too
    //    ambiguous to bet a QSO on.
    if (!opts.lidsMode && his.size() == 2 && result == CallMatch::Almost) {
        result = CallMatch::No;
    }

    // 2) A zero-penalty result that came from length-mismatch or via
    //    wildcards still counts as "Almost" (it's a partial copy, not
    //    a confirmed match).
    if (result == CallMatch::Yes) {
        const bool lenMismatch = his.size() != mine.size();
        const bool hasWildcard = his.find('?') != std::string_view::npos;
        if (lenMismatch || hasWildcard) {
            result = CallMatch::Almost;
        }
    }

    // 3) If the heard call has fewer than 2 non-wildcard characters,
    //    we don't have enough information to claim any match.
    if (countNonWildcards(his) < 2) {
        result = CallMatch::No;
    }

    // 4) LID mishearing: random Yes→Almost or Almost→Yes flips.
    //    Only applied to longer heard calls (>3) to avoid swamping the
    //    short-call ambiguity case above.
    if (opts.lidsMode && his.size() > 3) {
        if (result == CallMatch::Yes) {
            if (rng.uniform01() < kMishearStandardProb) {
                result = CallMatch::Almost;
            }
        } else if (result == CallMatch::Almost) {
            if (rng.uniform01() < kMishearLidProb) {
                result = CallMatch::Yes;
            }
        }
    }

    return result;
}

}  // namespace mr::sim
