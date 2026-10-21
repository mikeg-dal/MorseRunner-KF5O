// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of tests/scoring/test_call_to_score.cpp and test_extract_prefix.cpp,
// plus the golden comparison against Fixtures/scoring/prefix.json
// (golden_scoring.cpp, tag cpp-qt-reference).

import MRDSP
import MRScoring
import MRTestSupport
import Testing

private struct PrefixFixture: Decodable {
    let masterCount: Int
    let calls: [String]
    let prefix: [String]
    let score: [Int]
}

@Test func prefixAndScoreMatchCpp() throws {
    let f = try Fixtures.json(PrefixFixture.self, "scoring/prefix.json")
    #expect(f.masterCount == 32668)
    #expect(f.calls.count == f.prefix.count && f.calls.count == f.score.count)
    var prefixMismatches: [String] = []
    var scoreMismatches: [String] = []
    for (i, c) in f.calls.enumerated() {
        if !extractPrefix(c).utf8.elementsEqual(f.prefix[i].utf8) { prefixMismatches.append(c) }
        if callToScore(c) != f.score[i] { scoreMismatches.append(c) }
    }
    #expect(prefixMismatches.isEmpty, "\(prefixMismatches.prefix(20))")
    #expect(scoreMismatches.isEmpty, "\(scoreMismatches.prefix(20))")
}

// Pascal CallToScore reference re-implementation (same recurrence).
private func pascalReference(_ call: String) -> Int {
    var r = -1
    for c in encodeMessage(call) {
        if c == "." || c == " " { r += 2 } else if c == "-" { r += 4 }
    }
    return r
}

@Test func callToScoreEmptyStringReturnsMinusOne() {
    #expect(callToScore("") == -1)
}

@Test(arguments: ["A", "K", "N", "1", "9"])
func callToScoreSingleCharCalls(_ c: String) {
    #expect(callToScore(c) == pascalReference(c))
}

@Test(arguments: ["K1ABC", "VE3NEA", "P29SX", "W3LPL", "JA1XYZ", "DL5MW", "ZL1AAS", "KF5O"])
func callToScoreRealWorldCallsigns(_ call: String) {
    #expect(callToScore(call) == pascalReference(call))
}

@Test func callToScoreLongerCallsScoreHigher() {
    #expect(callToScore("E") < callToScore("T"))
    #expect(callToScore("KF5O") > callToScore("E"))
}

@Test func callToScoreIsCaseInsensitive() {
    #expect(callToScore("KF5O") == callToScore("kf5o"))
    #expect(callToScore("KF5O") == callToScore("Kf5o"))
}

// Vectors hand-traced against Pascal Log.pas:157-203.
@Test(arguments: [
    ("K1ABC", "K1"), ("VE3NEA", "VE3"), ("P29SX", "P29"), ("W3LPL", "W3"),
    ("JA1XYZ", "JA1"), ("AA1ZZ", "AA1"),
    ("VE3NEA/QRP", "VE3"), ("VE3NEA/MM", "VE3"), ("VE3NEA/M", "VE3"), ("VE3NEA/P", "VE3"),
    ("VE3NEA/W1", "W1"),   // S2 shorter; result = W1
    ("K/N1MM", "K0"),      // letter single-char K is shorter; '0' appended
    ("VE3NEA/0", "VE0"),   // Dig=0 replaces VE3's '3'
    ("9/VE3NEA", "VE9"),   // Dig=9 replaces VE3's '3'
    ("/K1ABC", "K1"),      // leading slash skipped
    ("K1ABC/", "K1"),      // trailing slash trimmed
    ("AB", "AB0"),         // no digit → append '0'
    ("K", ""),             // length < 2 after sentinel strip → empty
])
func extractPrefixPascalTraceVectors(_ call: String, _ expected: String) {
    #expect(extractPrefix(call) == expected)
}

@Test func extractPrefixTruncatesToFiveChars() {
    #expect(extractPrefix("ABCDEFGH1JKL").count == 5)
}

@Test func extractPrefixEmptyInputReturnsEmpty() {
    #expect(extractPrefix("") == "")
}

@Test func extractPrefixResultStillHasSlashIsInvalid() {
    // "/A/B": p=1, result=Copy(2..)="A/B"; the post-split '/' check fires.
    #expect(extractPrefix("/A/B") == "")
}
