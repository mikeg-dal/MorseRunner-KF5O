// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "scoring/ExtractPrefix.h"

#include <gtest/gtest.h>

#include <string>

namespace {

struct Case {
    const char* call;
    const char* expected;
    const char* why;
};

}  // namespace

// Vectors hand-traced against Pascal Log.pas:157-203. Each entry is
// (input, expected, rationale) so a future maintainer can re-derive
// any value without re-reading the algorithm.
TEST(ExtractPrefix, PascalTraceVectors) {
    const Case cases[] = {
        // No slash, trailing letters dropped, last is already digit.
        {"K1ABC",  "K1",  "trailing letters ABC dropped, '1' is digit"},
        {"VE3NEA", "VE3", "trailing letters NEA dropped, '3' is digit"},
        {"P29SX",  "P29", "trailing letters SX dropped, '9' is digit"},
        {"W3LPL",  "W3",  "trailing letters LPL dropped"},
        {"JA1XYZ", "JA1", "trailing letters XYZ dropped"},
        {"AA1ZZ",  "AA1", "trailing letters ZZ dropped"},

        // Portable suffix /QRP stripped first; then normal path.
        {"VE3NEA/QRP", "VE3", "/QRP stripped, then VE3NEA → VE3"},
        {"VE3NEA/MM",  "VE3", "/MM stripped, then VE3NEA → VE3"},
        {"VE3NEA/M",   "VE3", "/M stripped, then VE3NEA → VE3"},
        {"VE3NEA/P",   "VE3", "/P stripped, then VE3NEA → VE3"},

        // Slash split: shorter wins, but a single-digit alternate
        // sets `Dig` and replaces the last digit on the OTHER side.
        // VE3NEA/W1: S1=VE3NEA, S2=W1 → S2 shorter → result = W1
        //   (no Dig since S2 is multi-char). W1 already ends in
        //   digit, no trailing letters. Result = "W1".
        {"VE3NEA/W1", "W1", "S2 shorter; result = W1"},

        // K/N1MM: S1=K (one char, but a letter not a digit; Pascal's
        // `(Length(S1) = 1) and (S1[1] in DIGITS)` is false because K
        // isn't a digit, so we fall through to the length compare.
        // S1.size()=1 <= S2.size()=4, so result=S1="K". K has no
        // digit, append '0'. Result="K0".
        {"K/N1MM", "K0", "letter single-char K is shorter; '0' appended"},

        // VE3NEA/0: S2 is the single digit. dig="0", result=S1=
        // VE3NEA. Process VE3NEA → VE3, then back replace last char
        // with dig → VE0.
        {"VE3NEA/0", "VE0", "Dig=0 replaces VE3's '3' → VE0"},

        // 9/VE3NEA: S1 is single digit. dig="9", result=S2=VE3NEA.
        // Process VE3NEA → VE3, then back replace last char with dig
        // → VE9.
        {"9/VE3NEA", "VE9", "Dig=9 replaces VE3's '3' → VE9"},

        // Leading slash: skip the leading slash and treat rest as
        // bare call. /K1ABC → "K1ABC" → "K1".
        {"/K1ABC", "K1", "leading slash skipped"},

        // Trailing slash (not /M /P /QRP): everything before slash.
        {"K1ABC/", "K1", "trailing slash trimmed"},

        // Two-char call no digit: append '0'.
        {"AB", "AB0", "no digit → append '0'"},

        // Single-character input after the modifier strip is invalid.
        {"K", "", "length < 2 after sentinel strip → empty"},
    };

    for (const auto& c : cases) {
        SCOPED_TRACE(::testing::Message()
                     << "call='" << c.call << "' why=" << c.why);
        EXPECT_EQ(mr::scoring::extractPrefix(c.call), c.expected);
    }
}

TEST(ExtractPrefix, TruncatesToFiveChars) {
    // Pathological: a hypothetical call with a six-char prefix block
    // before the digit. The Pascal `Result := Copy(Result, 1, 5)`
    // truncates to 5.
    EXPECT_EQ(mr::scoring::extractPrefix("ABCDEFGH1JKL").size(),
              std::size_t{5});
}

TEST(ExtractPrefix, EmptyInputReturnsEmpty) {
    EXPECT_EQ(mr::scoring::extractPrefix(""), "");
}

TEST(ExtractPrefix, ResultStillHasSlashIsInvalid) {
    // After the modifier strip we still have a /, and the split
    // produces a piece that itself contains '/'. Pascal explicitly
    // returns "" in that case. Constructing such a case requires a
    // three-slash input.
    // Input "A/B/C": collapse // → /; first / at index 1 (Pascal
    // p=2). S1="A", S2="B/C". A is single-letter not-digit, so
    // length compare: 1 <= 3, S1="A" wins, no '/' in result → "A"
    // → "A0". So this isn't actually a trigger. The trigger requires
    // the post-split result to still have '/'.
    // Use input "/A/B" instead: after suffix-strip no change. p=1,
    // result=Copy(2..)="A/B". The post-check `if Pos('/', Result) >
    // 0 then Result := ''` fires.
    EXPECT_EQ(mr::scoring::extractPrefix("/A/B"), "");
}
