// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of the data side of Log.pas: the QSO list, SaveQso's bookkeeping,
// CheckErr, UpdateStats / UpdateStatsHst, ShowRate and PaintHisto's bins.
// Pure C++ with no Qt or simulation dependency so it can be unit-tested
// and owned by the GUI thread (where Pascal's Log unit lived).
//
// The one piece of Log.pas this class does not do itself is the truth
// lookup: Pascal reaches into Tst.Stations for a finished DX station with
// the same call (DataToLastQso). In the port that lookup runs on the sim
// thread, which reports back; the GUI then calls applyTruth().

#pragma once

#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mr::scoring {

struct Qso {
    double t = 0.0;          // contest time, seconds since Run (Pascal: T)
    std::string call;        // as logged, '?' stripped
    std::string trueCall;    // filled from the DX station's own record
    int rst = 0;
    int trueRst = 0;
    int nr = 0;
    int trueNr = 0;
    std::string pfx;         // WPX prefix, or the CallToScore value in HST
    bool dupe = false;
    std::string err = "NIL"; // "   " clean, else NIL / DUP / RST / "NR "
};

struct ScoreRow {
    int pts = 0;
    int mul = 0;
    int score = 0;
};

struct Stats {
    ScoreRow raw;
    ScoreRow verified;
};

class QsoLog {
public:
    static constexpr int kHistogramBins = 48;
    static constexpr int kHistogramBinMinutes = 5;

    // Log.pas SaveQso guard: call at least 3 chars, RST exactly 3, NR
    // not empty. Pascal beeps and refuses to log otherwise.
    [[nodiscard]] static bool entryIsValid(std::string_view call,
                                           std::string_view rst,
                                           std::string_view nr) noexcept;

    // Log.pas Clear.
    void clear() noexcept { qsos_.clear(); }

    // Log.pas SaveQso (minus the DX lookup, see the file comment).
    // Strips '?' from the call, computes the prefix, marks a dupe when an
    // earlier *clean* QSO has the same call, and runs CheckErr. With no
    // truth yet the new entry is NIL until applyTruth() fills it.
    const Qso& add(double tSeconds, std::string_view callAsTyped, int rst,
                   int nr, bool hstMode);

    // TDxStation.DataToLastQso + CheckErr. Applies only when `call`
    // matches the most recent entry (Pascal compares MyCall to the last
    // QSO's call). Returns true when the last entry changed.
    bool applyTruth(std::string_view call, int trueRst, int trueNr);

    // Log.pas UpdateStats (WPX-style) or UpdateStatsHst. Pascal
    // recomputes from the whole list: Raw counts every entry (dupes and
    // NILs included) and an empty prefix still counts as a multiplier.
    [[nodiscard]] Stats stats(bool hstMode) const;

    // Log.pas ShowRate: QSOs in the last min(5 min, elapsed), scaled to
    // an hourly rate. Empty when no time has elapsed (Pascal exits and
    // leaves the label untouched).
    [[nodiscard]] std::optional<int> rate(double nowSeconds) const;

    // Log.pas PaintHisto bins: QSOs per 5-minute block.
    [[nodiscard]] std::array<int, kHistogramBins> histogram() const;

    // Log.pas LastQsoToScreen for entry `index`. The Sent NR column is
    // RichEdit1.Lines.Count in Pascal, i.e. the entry's 1-based position
    // (header line + earlier rows). The last 3 characters are the error
    // tag, which the log view colours red.
    [[nodiscard]] std::string formatRow(std::size_t index, int sentRst) const;

    [[nodiscard]] const std::vector<Qso>& qsos() const noexcept { return qsos_; }
    [[nodiscard]] bool empty() const noexcept { return qsos_.empty(); }

private:
    void checkErrLast();

    std::vector<Qso> qsos_;
};

}  // namespace mr::scoring
