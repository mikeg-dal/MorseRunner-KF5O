// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reference data for the Swift port's MRScoring module:
//   scoring/prefix.json  extractPrefix + callToScore for every Master.dta
//                        call plus hand-picked portable / malformed cases
//   scoring/crc32.json   calculateCrc32 (seed $C90C2086 and others) and
//                        stamped PopupScoreWpx lines
//   scoring/qsolog.json  a QsoLog scenario (ops replayed by the Swift
//                        test) with per-op results, rows, stats, rates
//                        and histogram, in WPX and HST mode
//   scoring/edges.json   boundary cases (extractPrefix / callToScore /
//                        CRC32 on odd and non-ASCII input, QsoLog rows,
//                        rate and histogram at the edges). Strings are
//                        hex-encoded bytes so non-UTF-8 results (a
//                        multibyte character cut by the 5-byte prefix
//                        truncation) survive the JSON round trip.

#include "golden_io.h"

#include "core/Random.h"
#include "scoring/CallToScore.h"
#include "scoring/Crc32.h"
#include "scoring/ExtractPrefix.h"
#include "scoring/QsoLog.h"
#include "simulation/CallsignDb.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

using namespace golden;

namespace {

std::vector<std::string> masterCalls() {
    // golden binary lives in <build>/tools/golden; Master.dta in the repo.
    const std::filesystem::path src = std::filesystem::path(__FILE__).parent_path();
    const auto dta = (src / ".." / ".." / "resources" / "data" / "Master.dta").string();
    mr::sim::CallsignDb db;
    if (!db.loadFromFile(dta)) {
        std::fprintf(stderr, "cannot load %s\n", dta.c_str());
        std::exit(1);
    }
    // CallsignDb has no enumerator; draining it with pickAndRemoveCall
    // yields every (deduplicated) call exactly once.
    auto& rng = mr::core::Random::instance();
    rng.reseed(1);
    std::vector<std::string> calls;
    const std::size_t n = db.size();
    calls.reserve(n);
    for (std::size_t i = 0; i < n; ++i) calls.push_back(db.pickAndRemoveCall(rng));
    std::sort(calls.begin(), calls.end());
    return calls;
}

const std::vector<std::string> kTricky = {
    "", "K", "1", "/", "//", "K/", "/K", "AB", "A1", "1A", "11", "K1", "E7",
    "W1AW", "W1AW/P", "W1AW/M", "W1AW/MM", "W1AW/QRP", "W1AW/QRP/P", "W1AW/P/QRP",
    "W1AW/PM", "W1AW/MP", "W1AW/QRPP", "QRP", "/QRP", "/P", "/M", "/MM", "P/QRP",
    "VE3/W1AW", "W1AW/VE3", "W1AW/3", "3/W1AW", "W1AW/33", "W1AW//3", "W1AW///3",
    "VE3NEA/W1", "K/N1MM", "VE3NEA/0", "9/VE3NEA", "/K1ABC", "K1ABC/", "/A/B",
    "A/B/C", "A//B", "KH6/W1AW/P", "DL/W1AW/QRP", "W1AW/KH6/MM", "PA/ON4UN",
    "ABCDEFGH1JKL", "3DA0AB", "4X4AB", "9A1A", "T77C", "XX9X", "VP2E/K1ABC",
    "w1aw", "w1aw/p", "W1A?W", "K1ABC/P|", "K1|ABC", "R1ANC", "UA0LLL", "HB0/DL1ABC",
    "TO5A", "JD1/JA1XYZ", "W1AW/P/P", "W1AW/MM/QRP", "1/2", "12/3", "1/23",
    "AB/CD", "ABC/DE", "A/BC", "KF5O", "P29SX", "N0A", "ZZZZZZ", "Q", "QQ", "QQQ",
    "?", "K1???", "Grüße/3",
};

void dumpPrefix() {
    std::vector<std::string> calls = kTricky;
    const auto master = masterCalls();
    calls.insert(calls.end(), master.begin(), master.end());
    std::vector<std::string> pfx;
    std::vector<int> score;
    for (const auto& c : calls) {
        pfx.push_back(mr::scoring::extractPrefix(c));
        score.push_back(mr::scoring::callToScore(c));
    }
    writeText("scoring/prefix.json",
              "{\"masterCount\":" + num(master.size()) + ",\"calls\":" + arr(calls)
                  + ",\"prefix\":" + arr(pfx) + ",\"score\":" + arr(score) + "}");
}

void dumpCrc() {
    std::vector<std::string> s = {
        "", " ", "A", "a", "123456789", "The quick brown fox jumps over the lazy dog",
        "2026-10-20 KF5O 123 45 ", "2006-01-01 VE3NEA 0 0 ", "2026-01-01  0 0 ",
        "1999-12-31 W1AW/P 999 999 ", "Grüße", "[]{}\"\\",
    };
    // Every single byte value 0x20..0x7E as a one-char string.
    for (int c = 0x20; c < 0x7F; ++c) s.emplace_back(1, static_cast<char>(c));
    // Score lines in PopupScoreWpx form for a spread of calls / numbers.
    auto& rng = mr::core::Random::instance();
    rng.reseed(7);
    const char* calls[] = {"KF5O", "VE3NEA", "W1AW", "DL5MW", "JA1XYZ", "P29SX", "N0A/P"};
    for (int i = 0; i < 60; ++i) {
        char b[96];
        std::snprintf(b, sizeof b, "20%02d-%02d-%02d %s %d %d ", rng.uniformInt(30),
                      1 + rng.uniformInt(12), 1 + rng.uniformInt(28),
                      calls[rng.uniformInt(7)], rng.uniformInt(2000), rng.uniformInt(800));
        s.emplace_back(b);
    }
    const unsigned seeds[] = {0xC90C2086u, 0u, 0xFFFFFFFFu, 0x12345678u};
    std::string j = "{\"strings\":" + arr(s) + ",\"seeds\":[";
    for (std::size_t i = 0; i < 4; ++i) j += (i ? "," : "") + num(seeds[i]);
    j += "],\"crc\":[";
    for (std::size_t k = 0; k < 4; ++k) {
        std::vector<unsigned> v;
        for (const auto& x : s) v.push_back(mr::scoring::calculateCrc32(x, seeds[k]));
        j += (k ? "," : "") + arr(v);
    }
    // MainWindow::onContestFinished stamp: inner + "[%08X]".
    std::vector<std::string> stamped;
    for (const auto& x : s) {
        char b[16];
        std::snprintf(b, sizeof b, "[%08X]", mr::scoring::calculateCrc32(x, 0xC90C2086u));
        stamped.push_back(x + b);
    }
    j += "],\"stamped\":" + arr(stamped) + "}";
    writeText("scoring/crc32.json", j);
}

struct Op {
    bool isAdd;
    double t;
    std::string call;
    int rst;
    int nr;
};

std::vector<Op> makeOps() {
    auto& rng = mr::core::Random::instance();
    rng.reseed(2026);
    const char* pool[] = {"W1AW", "K1ABC", "VE3NEA", "VE3NEA/P", "DL5MW", "JA1XYZ",
                          "W1AW/3", "VE3/W1AW", "K/N1MM", "P29SX", "N0A", "ZL1AAS",
                          "KF5O/QRP", "AB", "OH2BH", "F6ABC/MM"};
    std::vector<Op> ops;
    double t = 3.25;
    for (int i = 0; i < 400; ++i) {
        t += 0.5 + 60.0 * static_cast<double>(rng.uniform01()) * static_cast<double>(rng.uniform01());
        std::string call = pool[rng.uniformInt(16)];
        if (rng.uniformInt(10) == 0) call.insert(1, "?");
        const int rst = rng.uniformInt(8) == 0 ? 579 : 599;
        const int nr = 1 + rng.uniformInt(9999);
        ops.push_back({true, t, call, rst, nr});
        const int k = rng.uniformInt(10);
        if (k == 0) continue;  // NIL: no truth arrives
        std::string tc = call;
        tc.erase(std::remove(tc.begin(), tc.end(), '?'), tc.end());
        if (k == 1) tc = pool[rng.uniformInt(16)];  // maybe-wrong station
        const int trst = k == 2 ? 559 : rst;
        const int tnr = k == 3 ? nr + 1 : nr;
        ops.push_back({false, 0.0, tc, trst, tnr});
    }
    // Land some entries exactly on bin edges and past the 240-minute end.
    for (double edge : {14399.9995, 14400.0, 15000.0}) {
        ops.push_back({true, edge, "W1AW", 599, 1});
        ops.push_back({false, 0.0, "W1AW", 599, 1});
    }
    return ops;
}

std::string runScenario(const std::vector<Op>& ops, bool hst) {
    mr::scoring::QsoLog log;
    std::vector<std::string> errs;
    std::vector<int> applied;  // -1 for add, else 0/1
    for (const auto& op : ops) {
        if (op.isAdd) {
            log.add(op.t, op.call, op.rst, op.nr, hst);
            applied.push_back(-1);
        } else {
            applied.push_back(log.applyTruth(op.call, op.rst, op.nr) ? 1 : 0);
        }
        errs.push_back(log.qsos().back().err);
    }
    std::vector<std::string> rows, pfx;
    std::vector<int> dupe;
    for (std::size_t i = 0; i < log.qsos().size(); ++i) {
        rows.push_back(log.formatRow(i, i % 3 == 0 ? 599 : 579));
        pfx.push_back(log.qsos()[i].pfx);
        dupe.push_back(log.qsos()[i].dupe ? 1 : 0);
    }
    const auto st = log.stats(hst);
    // Times before the first QSO count every (future) entry; keep the
    // smallest positive time large enough that the rate fits in an int
    // (the C++ double→int conversion in delphiRound is UB past that).
    std::vector<double> rateT = {-1.0, 0.0, 0.001, 0.5, 1.0, 59.9, 60.0, 299.0, 300.0, 301.0};
    for (double x = 7.0; x < 16000.0; x += 97.3) rateT.push_back(x);
    for (const auto& op : ops) if (op.isAdd) rateT.push_back(op.t);
    std::vector<int> rates;
    for (double x : rateT) rates.push_back(log.rate(x).value_or(-1));
    const auto h = log.histogram();
    return "{\"hst\":" + std::string(hst ? "true" : "false") + ",\"errs\":" + arr(errs)
         + ",\"applied\":" + arr(applied) + ",\"rows\":" + arr(rows) + ",\"pfx\":" + arr(pfx)
         + ",\"dupe\":" + arr(dupe) + ",\"stats\":["
         + arr(std::vector<int>{st.raw.pts, st.raw.mul, st.raw.score, st.verified.pts,
                                st.verified.mul, st.verified.score})
         + "],\"rateT\":" + arr(rateT) + ",\"rate\":" + arr(rates)
         + ",\"histogram\":" + arr(std::vector<int>(h.begin(), h.end())) + "}";
}

void dumpQsoLog() {
    const auto ops = makeOps();
    std::string j = "{\"ops\":[";
    for (std::size_t i = 0; i < ops.size(); ++i) {
        const auto& o = ops[i];
        j += (i ? "," : "") + std::string("{\"add\":") + (o.isAdd ? "true" : "false")
           + ",\"t\":" + num(o.t) + ",\"call\":" + str(o.call) + ",\"rst\":" + num(o.rst)
           + ",\"nr\":" + num(o.nr) + "}";
    }
    j += "],\"runs\":[" + runScenario(ops, false) + "," + runScenario(ops, true) + "]}";
    writeText("scoring/qsolog.json", j);
}


std::string hex(const std::string& s) {
    static const char* d = "0123456789abcdef";
    std::string o;
    for (const unsigned char c : s) {
        o += d[c >> 4];
        o += d[c & 15];
    }
    return o;
}

std::vector<std::string> hexAll(const std::vector<std::string>& v) {
    std::vector<std::string> o;
    for (const auto& s : v) o.push_back(hex(s));
    return o;
}

void dumpEdges() {
    using mr::scoring::QsoLog;
    // extractPrefix / callToScore. "\xC3\xA9" = U+00E9, "\xE2\x82\xAC" =
    // U+20AC: the 5-byte truncation can cut either in half.
    const std::vector<std::string> calls = {
        "", "/", "//", "///", "////", "A/B/C", "1/2", "K1ABC/QRP/P", "K1ABC/P/QRP",
        "k1abc", "ve3nea/p", "k/n1mm", "/QRP|", "|", "||", "K1ABC||",
        "AB", "AB1", "ABC", "AB1C", "A1BCD", "AB/1", "1/AB", "XY/7", "7/XY",
        "K\xC3\xA9" "1", "\xC3\xA9\xC3\xA9\xC3\xA9" "1", "ABCD\xC3\xA9" "1",
        "ABC\xE2\x82\xAC" "1", "ABCD\xE2\x82\xAC" "9", "\xE2\x82\xAC/3", "W1AW/\xC3\xA9",
        "ABCDE12345", "ABCDEFG9", "K1ABC/QRPP", "K1ABC/MMM",
    };
    std::vector<std::string> pfx;
    std::vector<int> score;
    for (const auto& c : calls) {
        pfx.push_back(mr::scoring::extractPrefix(c));
        score.push_back(mr::scoring::callToScore(c));
    }
    const std::vector<std::string> crcStrings = {
        "\xC3\xA9", "Gr\xC3\xBC\xC3\x9F" "e", "\xE2\x82\xAC", "\xF0\x9F\x93\xBB",
        "2026-10-21 K\xC3\x89" "1ABC 12 3 ",
    };
    std::vector<unsigned> crc;
    for (const auto& s : crcStrings) crc.push_back(mr::scoring::calculateCrc32(s, 0xC90C2086u));

    // formatRow: negative numbers, long calls, t past 24 h, negative t,
    // output past the 159-byte snprintf buffer.
    struct RowIn { double t; std::string call; int rst; int nr; int sentRst; };
    const std::vector<RowIn> rowIn = {
        {0.0, "W1AW", -5, -12, -599},
        {12.4995, "ABCDEFGHIJKLMNOP", 599, 1, 599},
        {86400.0, "W1AW", 599, 1, 599},
        {90061.5, "W1AW", 599, 1, 599},
        {359999.9994, "K1ABC", 599, 12345, 599},
        {-1.0, "W1AW", 599, 1, 599},
        {-3661.0, "W1AW", 599, 1, 599},
        {1.0, std::string(200, 'A') + "1", 599, 1, 599},
        {2.0, "K\xC3\xA9" "1ABC", 599, 1, 599},
    };
    QsoLog rowLog;
    std::vector<std::string> rows;
    for (std::size_t i = 0; i < rowIn.size(); ++i) {
        const auto& r = rowIn[i];
        rowLog.add(r.t, r.call, r.rst, r.nr, false);
        rows.push_back(rowLog.formatRow(i, r.sentRst));
    }

    // Histogram on bin edges, negative and past-the-end times.
    const std::vector<double> histT = {
        -600.0, -1.0, -0.0, 0.0, 299.999, 300.0, 300.001, 599.0, 600.0, 900.0,
        1199.9999, 1200.0, 14099.0, 14100.0, 14399.0, 14400.0, 20000.0,
    };
    QsoLog histLog;
    for (double t : histT) histLog.add(t, "W1AW", 599, 1, false);
    const auto h = histLog.histogram();

    // Rate: exactly at the window edge, non-monotonic times, negative now.
    // (No tiny positive `now`: the rate overflows int and the C++
    // double-to-int conversion in delphiRound is UB.)
    const std::vector<double> rateLogT = {100.0, 400.0, 350.0, 700.0, 1000.0};
    QsoLog rateLog;
    for (double t : rateLogT) rateLog.add(t, "W1AW", 599, 1, false);
    const std::vector<double> rateNow = {
        -300.0, -0.0, 0.0, 100.0, 399.0, 400.0, 650.0, 700.0, 999.9, 1000.0,
        1300.0, 1300.0001, 1299.9999, 5000.0,
    };
    std::vector<int> rates;
    for (double x : rateNow) rates.push_back(rateLog.rate(x).value_or(-1));

    // entryIsValid on byte lengths.
    const std::vector<std::string> validCalls = {"K\xC3\xA9", "\xC3\xA9", "K1", "K1A", ""};
    const std::vector<std::string> validRst = {"599", "5\xC3\xA9", "\xE2\x82\xAC", "59"};
    std::vector<int> valid;
    for (const auto& c : validCalls)
        for (const auto& r : validRst)
            for (const char* n : {"", "1", "\xC3\xA9"})
                valid.push_back(QsoLog::entryIsValid(c, r, n) ? 1 : 0);

    std::string j = "{\"calls\":" + arr(hexAll(calls)) + ",\"prefix\":" + arr(hexAll(pfx))
                  + ",\"score\":" + arr(score) + ",\"crcStrings\":" + arr(hexAll(crcStrings))
                  + ",\"crc\":" + arr(crc) + ",\"rows\":[";
    for (std::size_t i = 0; i < rowIn.size(); ++i) {
        const auto& r = rowIn[i];
        j += (i ? "," : "") + std::string("{\"t\":") + num(r.t) + ",\"call\":" + str(hex(r.call))
           + ",\"rst\":" + num(r.rst) + ",\"nr\":" + num(r.nr) + ",\"sentRst\":"
           + num(r.sentRst) + ",\"row\":" + str(hex(rows[i])) + "}";
    }
    j += "],\"histT\":" + arr(histT)
       + ",\"histogram\":" + arr(std::vector<int>(h.begin(), h.end()))
       + ",\"rateLogT\":" + arr(rateLogT) + ",\"rateNow\":" + arr(rateNow)
       + ",\"rate\":" + arr(rates) + ",\"validCalls\":" + arr(hexAll(validCalls))
       + ",\"validRst\":" + arr(hexAll(validRst))
       + ",\"validNr\":" + arr(hexAll(std::vector<std::string>{"", "1", "\xC3\xA9"}))
       + ",\"valid\":" + arr(valid) + "}";
    writeText("scoring/edges.json", j);
}

}  // namespace

int main(int argc, char** argv) {
    init(argc, argv);
    dumpPrefix();
    dumpCrc();
    dumpQsoLog();
    dumpEdges();
    return 0;
}
