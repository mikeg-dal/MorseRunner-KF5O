// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MorseTable.h"

#include <gtest/gtest.h>

using namespace mr::dsp;

TEST(MorseTable, KnownLetters) {
    EXPECT_EQ(patternForChar('E'), ".");
    EXPECT_EQ(patternForChar('T'), "-");
    EXPECT_EQ(patternForChar('A'), ".-");
    EXPECT_EQ(patternForChar('N'), "-.");
    EXPECT_EQ(patternForChar('Q'), "--.-");
}

TEST(MorseTable, CaseInsensitive) {
    EXPECT_EQ(patternForChar('q'), patternForChar('Q'));
    EXPECT_EQ(patternForChar('a'), patternForChar('A'));
}

TEST(MorseTable, Digits) {
    EXPECT_EQ(patternForChar('0'), "-----");
    EXPECT_EQ(patternForChar('5'), ".....");
    EXPECT_EQ(patternForChar('9'), "----.");
}

TEST(MorseTable, Punctuation) {
    EXPECT_EQ(patternForChar('/'), "-..-.");
    EXPECT_EQ(patternForChar('.'), ".-.-.-");
    EXPECT_EQ(patternForChar('?'), "..--..");
}

TEST(MorseTable, UnknownReturnsEmpty) {
    EXPECT_TRUE(patternForChar('@').empty());
    EXPECT_TRUE(patternForChar('!').empty());
}

TEST(MorseTable, Prosigns) {
    EXPECT_EQ(patternForProsign("SK"), "...-.-");
    EXPECT_EQ(patternForProsign("AR"), ".-.-.");
    EXPECT_EQ(patternForProsign("ar"), patternForProsign("AR"));
    EXPECT_TRUE(patternForProsign("XX").empty());
}

TEST(MorseTable, EncodeMessageCq) {
    // "CQ" → "-.-." + " " + "--.-" + "~"
    // (terminal inter-letter gap replaced with '~').
    EXPECT_EQ(encodeMessage("CQ"), "-.-. --.-~");
}

TEST(MorseTable, EncodeMessageWithSpace) {
    // "E T" -> 'E' yields ". ", then user space adds ' ', then 'T' yields
    // "- ", then terminal ' ' becomes '~'. Net: ".  -~" (two spaces).
    EXPECT_EQ(encodeMessage("E T"), ".  -~");
}

TEST(MorseTable, EncodeIgnoresUnknown) {
    EXPECT_EQ(encodeMessage("E@T"), encodeMessage("ET"));
}

TEST(MorseTable, EncodeEmpty) {
    EXPECT_TRUE(encodeMessage("").empty());
}
