// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "scoring/QsoLog.h"

#include "core/DelphiRound.h"
#include "scoring/CallToScore.h"
#include "scoring/ExtractPrefix.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <set>

namespace mr::scoring {

namespace {

constexpr const char* kClean = "   ";

}  // namespace

bool QsoLog::entryIsValid(std::string_view call, std::string_view rst,
                          std::string_view nr) noexcept {
    return call.size() >= 3 && rst.size() == 3 && !nr.empty();
}

const Qso& QsoLog::add(double tSeconds, std::string_view callAsTyped, int rst,
                       int nr, bool hstMode) {
    Qso q;
    q.t = tSeconds;
    q.call.reserve(callAsTyped.size());
    for (const char c : callAsTyped) {
        if (c != '?') {
            q.call.push_back(c);
        }
    }
    q.rst = rst;
    q.nr = nr;
    q.pfx = hstMode ? std::to_string(callToScore(q.call)) : extractPrefix(q.call);

    // Pascal: dupe only against an earlier QSO with the same call that
    // was itself clean (Err = '   ').
    q.dupe = std::ranges::any_of(qsos_, [&](const Qso& e) {
        return e.call == q.call && e.err == kClean;
    });

    qsos_.push_back(std::move(q));
    checkErrLast();
    return qsos_.back();
}

bool QsoLog::applyTruth(std::string_view call, int trueRst, int trueNr) {
    if (qsos_.empty() || qsos_.back().call != call) {
        return false;
    }
    Qso& q = qsos_.back();
    q.trueCall = std::string(call);
    q.trueRst = trueRst;
    q.trueNr = trueNr;
    checkErrLast();
    return true;
}

void QsoLog::checkErrLast() {
    // Log.pas CheckErr — order matters: NIL beats DUP beats RST beats NR.
    Qso& q = qsos_.back();
    if (q.trueCall.empty()) {
        q.err = "NIL";
    } else if (q.dupe) {
        q.err = "DUP";
    } else if (q.trueRst != q.rst) {
        q.err = "RST";
    } else if (q.trueNr != q.nr) {
        q.err = "NR ";
    } else {
        q.err = kClean;
    }
}

Stats QsoLog::stats(bool hstMode) const {
    Stats s;
    if (hstMode) {
        // UpdateStatsHst: Score = sum of CallToScore; Pts/Mul unused.
        for (const Qso& q : qsos_) {
            const int pts = callToScore(q.call);
            s.raw.score += pts;
            if (q.err == kClean) {
                s.verified.score += pts;
            }
        }
        return s;
    }

    // UpdateStats: PfxList is a sorted, dupIgnore string list, so the
    // multiplier is the number of distinct prefixes (empty included).
    std::set<std::string> rawPfx;
    std::set<std::string> verPfx;
    for (const Qso& q : qsos_) {
        ++s.raw.pts;
        rawPfx.insert(q.pfx);
        if (q.err == kClean) {
            ++s.verified.pts;
            verPfx.insert(q.pfx);
        }
    }
    s.raw.mul = static_cast<int>(rawPfx.size());
    s.raw.score = s.raw.pts * s.raw.mul;
    s.verified.mul = static_cast<int>(verPfx.size());
    s.verified.score = s.verified.pts * s.verified.mul;
    return s;
}

std::optional<int> QsoLog::rate(double nowSeconds) const {
    if (nowSeconds <= 0.0) {
        return std::nullopt;
    }
    const double window = std::min(5.0 * 60.0, nowSeconds);
    int cnt = 0;
    for (auto it = qsos_.rbegin(); it != qsos_.rend(); ++it) {
        if (it->t > nowSeconds - window) {
            ++cnt;
        } else {
            break;
        }
    }
    return mr::core::delphiRound(static_cast<double>(cnt) / window * 3600.0);
}

std::array<int, QsoLog::kHistogramBins> QsoLog::histogram() const {
    std::array<int, kHistogramBins> bins{};
    for (const Qso& q : qsos_) {
        // Pascal: Trunc(T * 1440) div 5. Clamp: a QSO logged exactly at
        // the 240-minute limit would index past the 48-bin array.
        const int minute = static_cast<int>(q.t / 60.0);
        const int bin = std::clamp(minute / kHistogramBinMinutes, 0, kHistogramBins - 1);
        ++bins.at(static_cast<std::size_t>(bin));
    }
    return bins;
}

std::string QsoLog::formatRow(std::size_t index, int sentRst) const {
    const Qso& q = qsos_.at(index);
    // FormatDateTime(' hh:nn:ss  ', T): DecodeTime rounds to the
    // millisecond, then the seconds field drops the remainder.
    const long long totalMs = std::llround(q.t * 1000.0);
    const long long totalSec = totalMs / 1000;
    const int hh = static_cast<int>((totalSec / 3600) % 24);
    const int mm = static_cast<int>((totalSec / 60) % 60);
    const int ss = static_cast<int>(totalSec % 60);

    // Format('%-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s', ...). Delphi pads
    // but never truncates, same as printf.
    const int sentNr = static_cast<int>(index) + 1;
    std::array<char, 160> buf{};
    const int n = std::snprintf(
        buf.data(), buf.size(), " %02d:%02d:%02d  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s",
        hh, mm, ss, q.call.c_str(), q.rst, q.nr, sentRst, sentNr, q.pfx.c_str(),
        q.err.c_str());
    if (n < 0) {
        return {};
    }
    return {buf.data(), std::min(static_cast<std::size_t>(n), buf.size() - 1)};
}

}  // namespace mr::scoring
