// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Pins QsoLog to the rules in Log.pas (SaveQso, CheckErr, UpdateStats,
// UpdateStatsHst, ShowRate, PaintHisto, LastQsoToScreen).

#include "scoring/QsoLog.h"

#include "scoring/CallToScore.h"

#include <gtest/gtest.h>

using mr::scoring::QsoLog;

TEST(QsoLog, EntryValidationMatchesSaveQso) {
    EXPECT_TRUE(QsoLog::entryIsValid("K1A", "599", "1"));
    EXPECT_FALSE(QsoLog::entryIsValid("K1", "599", "1"));    // call < 3
    EXPECT_FALSE(QsoLog::entryIsValid("K1AB", "59", "1"));   // RST != 3
    EXPECT_FALSE(QsoLog::entryIsValid("K1AB", "", "1"));
    EXPECT_FALSE(QsoLog::entryIsValid("K1AB", "599", ""));   // NR empty
}

TEST(QsoLog, NewEntryIsNilUntilTruthArrives) {
    QsoLog log;
    const auto& q = log.add(10.0, "W1AW", 599, 12, false);
    EXPECT_EQ(q.err, "NIL");
    EXPECT_TRUE(log.applyTruth("W1AW", 599, 12));
    EXPECT_EQ(log.qsos().back().err, "   ");
}

TEST(QsoLog, QuestionMarksAreStripped) {
    QsoLog log;
    EXPECT_EQ(log.add(0.0, "W1?W", 599, 1, false).call, "W1W");
}

TEST(QsoLog, TruthOnlyAppliesToLastEntry) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, false);
    log.add(1.0, "K1ABC", 599, 2, false);
    EXPECT_FALSE(log.applyTruth("W1AW", 599, 1));
    EXPECT_EQ(log.qsos()[0].err, "NIL");
}

TEST(QsoLog, CheckErrOrderNilDupRstNr) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, false);
    log.applyTruth("W1AW", 599, 1);                 // clean
    log.add(1.0, "W1AW", 599, 1, false);            // dupe, but no truth
    EXPECT_EQ(log.qsos().back().err, "NIL");        // NIL beats DUP
    log.applyTruth("W1AW", 599, 1);
    EXPECT_EQ(log.qsos().back().err, "DUP");

    log.add(2.0, "K1ABC", 579, 7, false);
    log.applyTruth("K1ABC", 599, 8);                // RST and NR both wrong
    EXPECT_EQ(log.qsos().back().err, "RST");        // RST beats NR

    log.add(3.0, "N2XYZ", 599, 7, false);
    log.applyTruth("N2XYZ", 599, 8);
    EXPECT_EQ(log.qsos().back().err, "NR ");
}

TEST(QsoLog, DupeOnlyAgainstEarlierCleanQso) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, false);            // stays NIL
    const auto& second = log.add(1.0, "W1AW", 599, 1, false);
    EXPECT_FALSE(second.dupe);
}

TEST(QsoLog, RawCountsEverythingVerifiedOnlyClean) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, false);
    log.applyTruth("W1AW", 599, 1);                 // clean, prefix W1
    log.add(1.0, "W1AW", 599, 1, false);
    log.applyTruth("W1AW", 599, 1);                 // DUP
    log.add(2.0, "K2ABC", 599, 3, false);           // NIL, prefix K2

    const auto s = log.stats(false);
    EXPECT_EQ(s.raw.pts, 3);
    EXPECT_EQ(s.raw.mul, 2);
    EXPECT_EQ(s.raw.score, 6);
    EXPECT_EQ(s.verified.pts, 1);
    EXPECT_EQ(s.verified.mul, 1);
    EXPECT_EQ(s.verified.score, 1);
}

TEST(QsoLog, HstScoreIsCallToScoreSum) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, true);
    log.applyTruth("W1AW", 599, 1);
    log.add(1.0, "K2ABC", 599, 2, true);            // NIL
    const auto s = log.stats(true);
    const int a = mr::scoring::callToScore("W1AW");
    const int b = mr::scoring::callToScore("K2ABC");
    EXPECT_EQ(s.raw.score, a + b);
    EXPECT_EQ(s.verified.score, a);
    EXPECT_EQ(log.qsos()[0].pfx, std::to_string(a));
}

TEST(QsoLog, RateUsesFiveMinuteWindow) {
    QsoLog log;
    EXPECT_FALSE(log.rate(0.0).has_value());
    // 2 QSOs in the first minute: rate = 2 / 60 s * 3600 = 120.
    log.add(10.0, "W1AW", 599, 1, false);
    log.add(20.0, "K2ABC", 599, 2, false);
    EXPECT_EQ(log.rate(60.0), 120);
    // At 10 minutes the window is the last 5 minutes, which is empty.
    EXPECT_EQ(log.rate(600.0), 0);
    log.add(590.0, "N3XYZ", 599, 3, false);
    EXPECT_EQ(log.rate(600.0), 12);  // 1 / 300 s * 3600
}

TEST(QsoLog, HistogramBinsAreFiveMinutes) {
    QsoLog log;
    log.add(0.0, "W1AW", 599, 1, false);
    log.add(299.0, "K2ABC", 599, 2, false);
    log.add(300.0, "N3XYZ", 599, 3, false);
    log.add(240.0 * 60.0, "N4XYZ", 599, 4, false);  // clamped into last bin
    const auto bins = log.histogram();
    EXPECT_EQ(bins[0], 2);
    EXPECT_EQ(bins[1], 1);
    EXPECT_EQ(bins[47], 1);
}

TEST(QsoLog, RowFormatMatchesLastQsoToScreen) {
    QsoLog log;
    log.add(3725.4, "W1AW", 579, 12, false);        // 01:02:05
    log.applyTruth("W1AW", 579, 12);
    log.add(3726.0, "K2ABC", 599, 3, false);
    EXPECT_EQ(log.formatRow(0, 599),
              " 01:02:05  W1AW          579 0012  599 0001  W1        ");
    EXPECT_EQ(log.formatRow(1, 599),
              " 01:02:06  K2ABC         599 0003  599 0002  K2     NIL");
}
