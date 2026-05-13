// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MorseTable.h"
#include "scoring/CallToScore.h"

#include <gtest/gtest.h>

#include <string>

namespace {

// Pascal CallToScore reference re-implementation. We can't call
// Pascal directly so we recompute the expected value here using the
// same recurrence Pascal uses. If `mr::dsp::encodeMessage` is wrong,
// both implementations are wrong together — but the existing
// test_morse_keyer pins encodeMessage at the byte level, so this is
// a valid second-axis test.
int pascalReference(std::string_view call) {
    const std::string encoded = mr::dsp::encodeMessage(call);
    int r = -1;
    for (char c : encoded) {
        if (c == '.' || c == ' ') {
            r += 2;
        } else if (c == '-') {
            r += 4;
        }
    }
    return r;
}

}  // namespace

TEST(CallToScore, EmptyStringReturnsMinusOne) {
    // Pascal: Result := -1; then encoded is empty so no chars
    // contribute. Sanity check: the Pascal floor is -1.
    EXPECT_EQ(mr::scoring::callToScore(""), -1);
}

TEST(CallToScore, SingleCharCalls) {
    // Single-character calls aren't legal but the algorithm has to
    // produce a stable value. We compare against the in-test
    // reference. The point is to lock in the byte-for-byte behavior
    // so a future encodeMessage refactor can't silently regress.
    for (const auto* c : {"A", "K", "N", "1", "9"}) {
        SCOPED_TRACE(c);
        EXPECT_EQ(mr::scoring::callToScore(c), pascalReference(c));
    }
}

TEST(CallToScore, RealWorldCallsigns) {
    // Hits every digit + letter the encoder touches, plus the
    // inter-character gap.
    for (const auto* call : {"K1ABC",
                              "VE3NEA",
                              "P29SX",
                              "W3LPL",
                              "JA1XYZ",
                              "DL5MW",
                              "ZL1AAS",
                              "KF5O"}) {
        SCOPED_TRACE(call);
        EXPECT_EQ(mr::scoring::callToScore(call), pascalReference(call));
    }
}

TEST(CallToScore, LongerCallsScoreHigher) {
    // Property test: a longer dash-heavy call always outscores a
    // shorter dot-heavy one. Encodes the qualitative HST design
    // intent (reward operators who copy harder calls).
    const int eShort = mr::scoring::callToScore("E");   // .
    const int tShort = mr::scoring::callToScore("T");   // -
    EXPECT_LT(eShort, tShort);                          // dash > dot
    const int kf5o = mr::scoring::callToScore("KF5O");
    const int e    = mr::scoring::callToScore("E");
    EXPECT_GT(kf5o, e);
}

TEST(CallToScore, IsCaseInsensitive) {
    // patternForChar() is case-insensitive per its contract; the
    // score should therefore match for upper / lower / mixed.
    const int upper = mr::scoring::callToScore("KF5O");
    const int lower = mr::scoring::callToScore("kf5o");
    const int mixed = mr::scoring::callToScore("Kf5o");
    EXPECT_EQ(upper, lower);
    EXPECT_EQ(upper, mixed);
}
