// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// CRC32 (Pascal VCL/Crc32.pas) against Fixtures/scoring/crc32.json.

import MRCore
import MRScoring
import MRTestSupport
import Testing

private struct CrcFixture: Decodable {
    let strings: [String]
    let seeds: [UInt32]
    let crc: [[UInt32]]
    let stamped: [String]
}

@Test func crc32MatchesCpp() throws {
    let f = try Fixtures.json(CrcFixture.self, "scoring/crc32.json")
    #expect(f.strings.count > 150)
    for (k, seed) in f.seeds.enumerated() {
        #expect(f.strings.map { calculateCrc32($0, seed: seed) } == f.crc[k])
    }
    #expect(f.strings.map(stampScoreLine) == f.stamped)
}

@Test func crc32Basics() {
    // No pre/post inversion: the empty string returns the seed.
    #expect(calculateCrc32("", seed: ScoringK.crc32Seed) == 0xC90C_2086)
    // With the conventional ~0 seed and a final inversion this is the
    // standard CRC-32 check value.
    #expect(~calculateCrc32("123456789", seed: 0xFFFF_FFFF) == 0xCBF4_3926)
    #expect(calculateCrc32(bytes: Array("KF5O".utf8), seed: 7)
            == calculateCrc32("KF5O", seed: 7))
}
