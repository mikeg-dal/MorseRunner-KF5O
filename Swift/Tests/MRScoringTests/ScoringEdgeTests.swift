// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Boundary cases of MRScoring against Fixtures/scoring/edges.json
// (tools/golden/golden_scoring.cpp, dumpEdges): every expected value
// comes from the C++ implementation. Strings in that file are hex bytes,
// so results that are not valid UTF-8 (a multibyte character cut by the
// 5-byte prefix truncation) compare exactly.

import MRCore
import MRScoring
import MRTestSupport
import Testing

private func unhex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var it = s.utf8.makeIterator()
    func nibble(_ c: UInt8) -> UInt8 { c <= 57 ? c - 48 : c - 87 }
    while let hi = it.next(), let lo = it.next() {
        out.append(nibble(hi) << 4 | nibble(lo))
    }
    return out
}

private func text(_ hex: String) -> String { String(decoding: unhex(hex), as: UTF8.self) }

private struct RowCase: Decodable {
    let t: Double
    let call: String
    let rst: Int
    let nr: Int
    let sentRst: Int
    let row: String
}

private struct Edges: Decodable {
    let calls: [String]
    let prefix: [String]
    let score: [Int]
    let crcStrings: [String]
    let crc: [UInt32]
    let rows: [RowCase]
    let histT: [Double]
    let histogram: [Int]
    let rateLogT: [Double]
    let rateNow: [Double]
    let rate: [Int]
    let validCalls: [String]
    let validRst: [String]
    let validNr: [String]
    let valid: [Int]
}

private struct PrefixCase: CustomTestStringConvertible {
    let call: [UInt8]
    let prefix: [UInt8]
    let score: Int
    var testDescription: String { String(decoding: call, as: UTF8.self) }
}

private func loadEdges() throws -> Edges {
    try Fixtures.json(Edges.self, "scoring/edges.json")
}

private func prefixCases() throws -> [PrefixCase] {
    let e = try loadEdges()
    return e.calls.indices.map {
        PrefixCase(call: unhex(e.calls[$0]), prefix: unhex(e.prefix[$0]), score: e.score[$0])
    }
}

@Test func edgesFixtureIsConsistent() throws {
    let e = try loadEdges()
    #expect(!e.calls.isEmpty && e.calls.count == e.prefix.count && e.calls.count == e.score.count)
    #expect(!e.crcStrings.isEmpty && e.crcStrings.count == e.crc.count)
    #expect(!e.rows.isEmpty)
    #expect(e.histogram.count == QsoLog.histogramBins)
    #expect(!e.rateNow.isEmpty && e.rateNow.count == e.rate.count)
    #expect(e.valid.count == e.validCalls.count * e.validRst.count * e.validNr.count)
}

// MARK: - extractPrefix / callToScore

@Test(arguments: try prefixCases())
private func extractPrefixBytesMatchCpp(_ c: PrefixCase) {
    #expect(extractPrefix(bytes: c.call) == c.prefix)
}

@Test(arguments: try prefixCases())
private func extractPrefixStringIsUtf8DecodingOfBytes(_ c: PrefixCase) {
    let call = String(decoding: c.call, as: UTF8.self)
    #expect(extractPrefix(call) == String(decoding: c.prefix, as: UTF8.self))
}

@Test(arguments: try prefixCases())
private func callToScoreMatchesCpp(_ c: PrefixCase) {
    #expect(callToScore(String(decoding: c.call, as: UTF8.self)) == c.score)
}

// Readable spot checks; the values are the C++ results in edges.json.
@Test(arguments: [
    ("/", ""), ("//", ""), ("///", ""), ("A/B/C", "A0"), ("1/2", "1"),
    ("K1ABC/QRP/P", "QR0"), ("K1ABC/P/QRP", "P0"), ("k1abc", "k1"), ("ve3nea/p", "p0"),
    ("AB1", "AB1"), ("ABC", "AB0"), ("AB/1", "AB1"), ("7/XY", "XY7"), ("||", "||0"),
    ("ABCDE12345", "ABCDE"),
])
func extractPrefixSpotChecks(_ call: String, _ want: String) {
    #expect(extractPrefix(call) == want)
}

@Test func truncationThatSplitsACharacter() {
    // "ABCDé1": the 5-byte cut keeps only the first byte of "é" (C3 A9).
    #expect(extractPrefix(bytes: Array("ABCD\u{E9}1".utf8)) == Array("ABCD".utf8) + [0xC3])
    // The String form cannot hold a lone C3; it decodes it as U+FFFD.
    #expect(extractPrefix("ABCD\u{E9}1") == "ABCD\u{FFFD}")
}

// MARK: - CRC32

@Test func crc32OfNonAsciiMatchesCpp() throws {
    let e = try loadEdges()
    for (s, want) in zip(e.crcStrings, e.crc) {
        #expect(calculateCrc32(text(s), seed: ScoringK.crc32Seed) == want, "\(text(s))")
        #expect(calculateCrc32(bytes: unhex(s), seed: ScoringK.crc32Seed) == want)
    }
}

// MARK: - QsoLog

@Test func formatRowEdgesMatchCpp() throws {
    let e = try loadEdges()
    var log = QsoLog()
    for (i, r) in e.rows.enumerated() {
        log.add(t: r.t, call: text(r.call), rst: r.rst, nr: r.nr, hstMode: false)
        let row = log.formatRow(i, sentRst: r.sentRst)
        #expect(Array(row.utf8) == unhex(r.row), "row \(i): \(row)")
    }
}

@Test func formatRowSpecificEdges() {
    var log = QsoLog()
    log.add(t: 0, call: "W1AW", rst: -5, nr: -12, hstMode: false)
    #expect(log.formatRow(0, sentRst: -599) == " 00:00:00  W1AW          -005 -0012  -599 0001  W1     NIL")
    log.add(t: 90061.5, call: "ABCDEFGHIJKLMNOP", rst: 599, nr: 1, hstMode: false)   // 25 h wraps
    #expect(log.formatRow(1, sentRst: 599) == " 01:01:01  ABCDEFGHIJKLMNOP  599 0001  599 0002  AB0    NIL")
    log.add(t: 1, call: String(repeating: "A", count: 200) + "1", rst: 599, nr: 1, hstMode: false)
    #expect(log.formatRow(2, sentRst: 599).utf8.count == 159)          // snprintf buffer cut
}

@Test func histogramEdgesMatchCpp() throws {
    let e = try loadEdges()
    var log = QsoLog()
    for t in e.histT { log.add(t: t, call: "W1AW", rst: 599, nr: 1, hstMode: false) }
    #expect(log.histogram() == e.histogram)
}

@Test func histogramBinBoundaries() {
    var log = QsoLog()
    for t in [-1.0, 299.999, 300.0, 599.999, 600.0, 14_399.0, 14_400.0, 1.0e9] {
        log.add(t: t, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    }
    let bins = log.histogram()
    #expect(bins[0] == 2)          // negative time clamps into the first bin
    #expect(bins[1] == 2)          // [300, 600)
    #expect(bins[2] == 1)          // 600 starts a new bin
    #expect(bins[47] == 3)         // 239:59, 240:00 and far past the end
    #expect(bins.reduce(0, +) == 8)
}

@Test func rateEdgesMatchCpp() throws {
    let e = try loadEdges()
    var log = QsoLog()
    for t in e.rateLogT { log.add(t: t, call: "W1AW", rst: 599, nr: 1, hstMode: false) }
    #expect(e.rateNow.map { log.rate(now: $0) ?? -1 } == e.rate)
}

@Test func rateWindowEdgeIsExclusive() {
    var log = QsoLog()
    log.add(t: 700, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    #expect(log.rate(now: 1000) == 0)         // t == now - 300: outside the window
    #expect(log.rate(now: 999.9) == 12)
    #expect(log.rate(now: -5) == nil)         // no elapsed time
    #expect(log.rate(now: .nan) == 0)         // no trap: nothing compares inside
}

@Test func rateStopsAtFirstOldEntryEvenIfLogIsUnsorted() {
    // ShowRate walks back from the newest entry and stops at the first
    // one outside the window, as Pascal does — later-listed but older
    // entries hide earlier-listed recent ones.
    var log = QsoLog()
    log.add(t: 950, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    log.add(t: 100, call: "K1ABC", rst: 599, nr: 2, hstMode: false)
    #expect(log.rate(now: 1000) == 0)
}

@Test func entryIsValidCountsBytes() throws {
    let e = try loadEdges()
    var got: [Int] = []
    for c in e.validCalls {
        for r in e.validRst {
            for n in e.validNr {
                got.append(QsoLog.entryIsValid(call: text(c), rst: text(r), nr: text(n)) ? 1 : 0)
            }
        }
    }
    #expect(got == e.valid)
    // "Ké" is 3 bytes: long enough, like the C++ size() check.
    #expect(QsoLog.entryIsValid(call: "K\u{E9}", rst: "599", nr: "1"))
    // "€" is one character but 3 bytes: a valid RST length to the C++.
    #expect(QsoLog.entryIsValid(call: "K1A", rst: "\u{20AC}", nr: "1"))
}

@Test func applyTruthOnEmptyLogDoesNothing() {
    var log = QsoLog()
    let applied = log.applyTruth(call: "W1AW", trueRst: 599, trueNr: 1)
    #expect(!applied)
    #expect(log.isEmpty)
}

@Test func nanTimeTraps() async {
    await #expect(processExitsWith: .failure) {
        var log = QsoLog()
        log.add(t: .nan, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    }
}

@Test func infiniteTimeTraps() async {
    await #expect(processExitsWith: .failure) {
        var log = QsoLog()
        log.add(t: -.infinity, call: "W1AW", rst: 599, nr: 1, hstMode: false)
    }
}

@Test func formatRowOutOfRangeTraps() async {
    await #expect(processExitsWith: .failure) {
        var log = QsoLog()
        log.add(t: 1, call: "W1AW", rst: 599, nr: 1, hstMode: false)
        _ = log.formatRow(1, sentRst: 599)
    }
}
