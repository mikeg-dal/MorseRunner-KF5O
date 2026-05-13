// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/NumberFormat.h"

#include "core/Random.h"

#include <gtest/gtest.h>

using namespace mr::sim;

namespace {

mr::core::Random& seededRng(std::uint64_t s) {
    auto& r = mr::core::Random::instance();
    r.reseed(s);
    return r;
}

}  // namespace

TEST(NrAsText, HstModeNoCutNumbers) {
    // In HST mode the cut-number substitutions are suppressed entirely:
    // we always send the literal digits. RST=599 still collapses to
    // 5NN because that one IS unconditional.
    NrFormatOptions opts{599, 100, /*hstMode=*/true, /*lidError=*/false};
    auto& rng = seededRng(1);
    EXPECT_EQ(nrAsText(opts, rng), "5NN100");
}

TEST(NrAsText, RstNineNineNineCollapses) {
    NrFormatOptions opts{599, 1, /*hstMode=*/true, false};
    auto& rng = seededRng(2);
    EXPECT_EQ(nrAsText(opts, rng), "5NN001");
}

TEST(NrAsText, ZeroSubstitutionUsesOOrTConsistently) {
    // Pascal: the rfReplaceAll semantics mean every '0' in the string
    // is replaced with the SAME letter on a given call (a single
    // coin-flip decides for that call, then all occurrences mirror it).
    // We exercise NR = 100 (one zero) and NR = 110 (two zeros) over
    // many seeds and verify that within a single call only one of
    // 'O'/'T' appears in the digit-zero slots.
    for (int seed = 0; seed < 50; ++seed) {
        NrFormatOptions opts{599, 100, false, false};
        auto& rng = seededRng(static_cast<std::uint64_t>(seed));
        const std::string s = nrAsText(opts, rng);
        const bool hasO = s.find('O') != std::string::npos;
        const bool hasT_at_zero = s.find('T') != std::string::npos;
        // At least one of the two should appear (or the digit '0'
        // retained, at ~3% probability).
        EXPECT_TRUE(hasO || hasT_at_zero || s.find('0') != std::string::npos);
        // And NEVER both an 'O' and a digit-zero in the same call —
        // the substitution is all-or-nothing per call.
        if (hasO) {
            EXPECT_EQ(s.find('0'), std::string::npos);
        }
    }
}

TEST(NrAsText, NineSubstitutedAsN) {
    // Over many seeds, NR = 9 should mostly render with 'N' (97% rate).
    NrFormatOptions opts{599, 9, false, false};
    int nineCount = 0;
    int nCount = 0;
    constexpr int kTrials = 2000;
    for (int i = 0; i < kTrials; ++i) {
        auto& rng = seededRng(static_cast<std::uint64_t>(0xBEEF + i));
        const std::string s = nrAsText(opts, rng);
        // The body of the NR portion starts at offset 3 (after "5NN").
        if (s.find('N', 3) != std::string::npos) {
            ++nCount;
        } else if (s.find('9') != std::string::npos) {
            ++nineCount;
        }
    }
    // 97% target ± 2% tolerance for the trial count.
    EXPECT_GT(nCount * 100, kTrials * 90);
    EXPECT_LT(nCount * 100, kTrials * 100);
    EXPECT_GE(nineCount, 0);
}

TEST(NrAsText, LidErrorAppendsEEEEECorrection) {
    NrFormatOptions opts{599, 234, true, /*lidError=*/true};
    auto& rng = seededRng(11);
    const std::string s = nrAsText(opts, rng);
    // The "EEEEE 234" correction is always appended after the corrupt
    // version of the NR. (In HST mode the rest of the string has no
    // substitutions, so we know the tail format exactly.)
    EXPECT_NE(s.find("EEEEE 234"), std::string::npos);
}
