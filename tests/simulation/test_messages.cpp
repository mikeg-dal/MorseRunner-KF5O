// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/Messages.h"

#include <gtest/gtest.h>

using namespace mr::sim;

TEST(Messages, EnumCountMatchesTableSize) {
    EXPECT_EQ(kMessageCount, 23U);
}

TEST(Messages, CqTemplateExact) {
    EXPECT_EQ(templateFor(Message::Cq), "CQ <my> TEST");
}

TEST(Messages, LongCqTemplateExact) {
    EXPECT_EQ(templateFor(Message::LongCq), "CQ CQ TEST <my> <my> TEST");
}

TEST(Messages, AllNonGarbageNonNoneHaveTemplates) {
    for (std::size_t i = 0; i < kMessageCount; ++i) {
        const Message m = static_cast<Message>(i);
        if (m == Message::None || m == Message::Garbage) {
            EXPECT_TRUE(templateFor(m).empty()) << nameOf(m);
        } else {
            EXPECT_FALSE(templateFor(m).empty()) << nameOf(m);
        }
    }
}

TEST(Messages, QsyHasDoubleSpace) {
    // Port-of-original quirk: the Pascal source spells out QSY as
    // `<his>  QSY QSY` (two spaces between <his> and QSY) — preserved
    // verbatim so the rendered envelope timing matches.
    EXPECT_EQ(templateFor(Message::Qsy), "<his>  QSY QSY");
}

TEST(Messages, R_Nr2HasTwoNumberSlots) {
    EXPECT_EQ(templateFor(Message::R_Nr2), "R <#> <#>");
}

TEST(Messages, MessageSetContains) {
    MessageSet s = messageSetOf(Message::Cq);
    s |= messageSetOf(Message::Tu);
    EXPECT_TRUE(contains(s, Message::Cq));
    EXPECT_TRUE(contains(s, Message::Tu));
    EXPECT_FALSE(contains(s, Message::B4));
    EXPECT_FALSE(contains(s, Message::None));
}

TEST(Messages, NoneAndOutOfRangeReturnEmptyName) {
    EXPECT_EQ(nameOf(Message::None), "None");
    // out-of-range cast — defensive guard, shouldn't crash.
    EXPECT_EQ(nameOf(static_cast<Message>(999)), "Unknown");
}
