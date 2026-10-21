// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MRTestSupport.Fixtures' raw Float32 reader (shared by every golden
// test), exercised here because MRAudioTests already links it.

import Foundation
import MRTestSupport
import Testing

@Suite struct FixturesTests {
    private func littleEndianBytes(_ values: [Float]) -> [UInt8] {
        values.flatMap { v -> [UInt8] in
            let b = v.bitPattern.littleEndian
            return (0..<4).map { UInt8(truncatingIfNeeded: b >> (8 * $0)) }
        }
    }

    @Test func decodesLittleEndianFloats() throws {
        let values: [Float] = [0, 1, -2.5, .pi, .leastNonzeroMagnitude, -.infinity]
        let floats = try Fixtures.floats(littleEndian: Data(littleEndianBytes(values)))
        #expect(floats == values)
    }

    @Test func readsFromAnUnalignedStart() throws {
        let values: [Float] = [1.5, -3, 42]
        let padded = Data([0xAA] + littleEndianBytes(values))
        // A Data slice starting at offset 1: its bytes are misaligned for Float.
        let slice = padded[padded.startIndex + 1 ..< padded.endIndex]
        let floats = try Fixtures.floats(littleEndian: slice)
        #expect(floats == values)
    }

    @Test func emptyDataIsEmpty() throws {
        let floats = try Fixtures.floats(littleEndian: Data())
        #expect(floats.isEmpty)
    }

    @Test(arguments: [1, 2, 3, 5, 11])
    func partialTrailingFloatThrows(byteCount: Int) {
        #expect(throws: Fixtures.FixtureError.self) {
            try Fixtures.floats(littleEndian: Data(repeating: 0, count: byteCount), path: "x.f32")
        }
    }

    @Test func bundledFixtureLoads() throws {
        let floats = try Fixtures.floats("dsp/agc_input.f32")
        #expect(!floats.isEmpty)
        #expect(floats.allSatisfy { $0.isFinite })
    }
}
