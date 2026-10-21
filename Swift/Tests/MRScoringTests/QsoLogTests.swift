// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of tests/scoring/test_qso_log.cpp (Log.pas SaveQso, CheckErr,
// UpdateStats, UpdateStatsHst, ShowRate, PaintHisto, LastQsoToScreen),
// plus a replay of the golden scenario in Fixtures/scoring/qsolog.json.

import MRScoring
import MRTestSupport
import Testing

private struct QsoOp: Decodable {
    let add: Bool
    let t: Double
    let call: String
    let rst: Int
    let nr: Int
}

private struct QsoRun: Decodable, CustomTestStringConvertible {
    let hst: Bool
    let errs: [String]
    let applied: [Int]
    let rows: [String]
    let pfx: [String]
    let dupe: [Int]
    let stats: [[Int]]
    let rateT: [Double]
    let rate: [Int]
    let histogram: [Int]
    var testDescription: String { hst ? "HST" : "WPX" }
}

private struct QsoFixture: Decodable {
    let ops: [QsoOp]
    let runs: [QsoRun]
}

private func loadQsoFixture() throws -> QsoFixture {
    try Fixtures.json(QsoFixture.self, "scoring/qsolog.json")
}

@Test func qsoFixtureHasBothModes() throws {
    #expect(try loadQsoFixture().runs.map(\.hst).sorted { !$0 && $1 } == [false, true])
}

@Test(arguments: try loadQsoFixture().runs)
private func qsoLogMatchesCppScenario(_ r: QsoRun) throws {
    let f = try loadQsoFixture()
    var log = QsoLog()
    var errs: [String] = []
    var applied: [Int] = []
    for op in f.ops {
        if op.add {
            log.add(t: op.t, call: op.call, rst: op.rst, nr: op.nr, hstMode: r.hst)
            applied.append(-1)
        } else {
            applied.append(log.applyTruth(call: op.call, trueRst: op.rst, trueNr: op.nr) ? 1 : 0)
        }
        errs.append(try #require(log.qsos.last).err)
    }
    #expect(errs == r.errs)
    #expect(applied == r.applied)
    let rows = log.qsos.indices.map { log.formatRow($0, sentRst: $0 % 3 == 0 ? 599 : 579) }
    #expect(rows == r.rows)
    #expect(log.qsos.map(\.pfx) == r.pfx)
    #expect(log.qsos.map { $0.dupe ? 1 : 0 } == r.dupe)
    let s = log.stats(hstMode: r.hst)
    #expect([s.raw.pts, s.raw.mul, s.raw.score, s.verified.pts, s.verified.mul,
             s.verified.score] == r.stats[0])
    #expect(r.rateT.map { log.rate(now: $0) ?? -1 } == r.rate)
    #expect(log.histogram() == r.histogram)
}

@Test func entryValidationMatchesSaveQso() {
    #expect(QsoLog.entryIsValid(call: "K1A", rst: "599", nr: "1"))
    #expect(!QsoLog.entryIsValid(call: "K1", rst: "599", nr: "1"))    // call < 3
    #expect(!QsoLog.entryIsValid(call: "K1AB", rst: "59", nr: "1"))   // RST != 3
    #expect(!QsoLog.entryIsValid(call: "K1AB", rst: "", nr: "1"))
    #expect(!QsoLog.entryIsValid(call: "K1AB", rst: "599", nr: ""))   // NR empty
}

@Test func newEntryIsNilUntilTruthArrives() {
    var log = QsoLog()
    let q = log.add(t: 10, call: "W1AW", rst: 599, nr: 12, hstMode: false)
    #expect(q.err == "NIL")
    let applied = log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 12)
    #expect(applied)
    #expect(log.qsos.last?.err == "   ")
}

@Test func questionMarksAreStripped() {
    var log = QsoLog()
    let q = log.add(t: 0, call: "W1?W", rst: 599, nr: 1, hstMode: false)
    #expect(q.call == "W1W")
}

@Test func truthOnlyAppliesToLastEntry() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.add(t: 1, call: "K1ABC", rst: 599, nr: 2, hstMode: false)
    let applied = log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)
    #expect(!applied)
    #expect(log.qsos[0].err == "NIL")
}

@Test func checkErrOrderNilDupRstNr() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)           // clean
    log.add(t: 1, call: "W1AW", rst: 599, nr: 1, hstMode: false)    // dupe, no truth
    #expect(log.qsos.last?.err == "NIL")                            // NIL beats DUP
    log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)
    #expect(log.qsos.last?.err == "DUP")

    log.add(t: 2, call: "K1ABC", rst: 579, nr: 7, hstMode: false)
    log.applyTruth(call: "K1ABC", trueRst: 599, trueNr: 8)          // RST and NR wrong
    #expect(log.qsos.last?.err == "RST")                            // RST beats NR

    log.add(t: 3, call: "N2XYZ", rst: 599, nr: 7, hstMode: false)
    log.applyTruth(call: "N2XYZ", trueRst: 599, trueNr: 8)
    #expect(log.qsos.last?.err == "NR ")
}

@Test func dupeOnlyAgainstEarlierCleanQso() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)    // stays NIL
    let second = log.add(t: 1, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    #expect(!second.dupe)
}

@Test func rawCountsEverythingVerifiedOnlyClean() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)           // clean, W1
    log.add(t: 1, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)           // DUP
    log.add(t: 2, call: "K2ABC", rst: 599, nr: 3, hstMode: false)   // NIL, K2
    let s = log.stats(hstMode: false)
    #expect(s.raw == ScoreRow(pts: 3, mul: 2, score: 6))
    #expect(s.verified == ScoreRow(pts: 1, mul: 1, score: 1))
}

@Test func hstScoreIsCallToScoreSum() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: true)
    log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)
    log.add(t: 1, call: "K2ABC", rst: 599, nr: 2, hstMode: true)   // NIL
    let s = log.stats(hstMode: true)
    let a = callToScore("W1AW")
    let b = callToScore("K2ABC")
    #expect(s.raw.score == a + b)
    #expect(s.verified.score == a)
    #expect(log.qsos[0].pfx == String(a))
}

@Test func rateUsesFiveMinuteWindow() {
    var log = QsoLog()
    #expect(log.rate(now: 0) == nil)
    log.add(t: 10, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.add(t: 20, call: "K2ABC", rst: 599, nr: 2, hstMode: false)
    #expect(log.rate(now: 60) == 120)     // 2 / 60 s * 3600
    #expect(log.rate(now: 600) == 0)      // last 5 minutes empty
    log.add(t: 590, call: "N3XYZ", rst: 599, nr: 3, hstMode: false)
    #expect(log.rate(now: 600) == 12)     // 1 / 300 s * 3600
}

@Test func histogramBinsAreFiveMinutes() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.add(t: 299, call: "K2ABC", rst: 599, nr: 2, hstMode: false)
    log.add(t: 300, call: "N3XYZ", rst: 599, nr: 3, hstMode: false)
    log.add(t: 240 * 60, call: "N4XYZ", rst: 599, nr: 4, hstMode: false)  // last bin
    let bins = log.histogram()
    #expect(bins.count == QsoLog.histogramBins)
    #expect(bins[0] == 2)
    #expect(bins[1] == 1)
    #expect(bins[47] == 1)
}

@Test func rowFormatMatchesLastQsoToScreen() {
    var log = QsoLog()
    log.add(t: 3725.4, call: "W1AW", rst: 579, nr: 12, hstMode: false)   // 01:02:05
    log.applyTruth(call: "W1AW", trueRst: 579, trueNr: 12)
    log.add(t: 3726.0, call: "K2ABC", rst: 599, nr: 3, hstMode: false)
    #expect(log.formatRow(0, sentRst: 599)
            == " 01:02:05  W1AW          579 0012  599 0001  W1        ")
    #expect(log.formatRow(1, sentRst: 599)
            == " 01:02:06  K2ABC         599 0003  599 0002  K2     NIL")
}

@Test func clearEmptiesTheLog() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.clear()
    #expect(log.isEmpty)
}
