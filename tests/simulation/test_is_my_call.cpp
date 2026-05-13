// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/IsMyCall.h"

#include "core/Random.h"

#include <gtest/gtest.h>

using namespace mr::sim;

namespace {

CallMatch run(std::string_view mine, std::string_view his, bool lids = false) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(42);
    return isMyCall({mine, his, lids}, rng);
}

}  // namespace

TEST(IsMyCall, ExactMatchIsYes) {
    EXPECT_EQ(run("VE3NEA", "VE3NEA"), CallMatch::Yes);
    EXPECT_EQ(run("KF5O", "KF5O"), CallMatch::Yes);
}

TEST(IsMyCall, CompletelyDifferentIsNo) {
    EXPECT_EQ(run("VE3NEA", "JA1XYZ"), CallMatch::No);
    EXPECT_EQ(run("KF5O", "G0ABC"), CallMatch::No);
}

TEST(IsMyCall, OneTypoIsAlmost) {
    // Single-character substitution → penalty 2 → Almost.
    EXPECT_EQ(run("VE3NEA", "VE3MEA"), CallMatch::Almost);
}

TEST(IsMyCall, WildcardDowngradesYesToAlmost) {
    // `?` matches any char but flags the result as partial copy.
    EXPECT_EQ(run("VE3NEA", "VE3?EA"), CallMatch::Almost);
}

TEST(IsMyCall, PartialTrailingIsAlmost) {
    // Heard "K1A" while DX is "K1ABC" — the trailing letters don't
    // penalize, but the length mismatch downgrades Yes → Almost.
    EXPECT_EQ(run("K1ABC", "K1A"), CallMatch::Almost);
}

TEST(IsMyCall, ShortHeardCallWithTypoIsNoWithoutLids) {
    // Length-2 heard call with non-LIDs mode AND a typo (DP yields
    // Almost) is forced to No — too short to bet a QSO on. Pascal:
    // DxOper.pas::IsMyCall, "callsign-specific corrections" block.
    EXPECT_EQ(run("VE3NEA", "VX", /*lids=*/false), CallMatch::No);
}

TEST(IsMyCall, CleanShortPrefixIsAlmost) {
    // Pure 2-char prefix without typo: DP=0 (Yes), then the length-
    // mismatch rule downgrades to Almost. The short-call corrective
    // only fires for DP-Almost results, NOT for DP-Yes results.
    EXPECT_EQ(run("VE3NEA", "VE", /*lids=*/false), CallMatch::Almost);
}

TEST(IsMyCall, TooFewNonWildcardsIsNo) {
    EXPECT_EQ(run("VE3NEA", "?"), CallMatch::No);
    EXPECT_EQ(run("VE3NEA", "V?"), CallMatch::No);
}

TEST(IsMyCall, LidsMishearingHappensSometimes) {
    // With LIDs on, occasional Yes→Almost (1%) and Almost→Yes (4%)
    // flips occur. We just verify the function doesn't crash and the
    // long-run distribution is dominated by the underlying classification.
    int yesCount = 0;
    int almostCount = 0;
    constexpr int kTrials = 1000;
    for (int i = 0; i < kTrials; ++i) {
        auto& rng = mr::core::Random::instance();
        rng.reseed(static_cast<std::uint64_t>(0xC0FFEE + i));
        const auto r = isMyCall({"VE3NEA", "VE3NEA", /*lids=*/true}, rng);
        if (r == CallMatch::Yes) ++yesCount;
        else if (r == CallMatch::Almost) ++almostCount;
    }
    // Exact match in LIDs mode: 99% Yes, 1% Almost — easy bounds.
    EXPECT_GT(yesCount * 100, kTrials * 95);
    EXPECT_LT(almostCount * 100, kTrials * 5);
}
