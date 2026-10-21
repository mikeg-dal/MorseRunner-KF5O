// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// CallsignDb parsing edge cases (C++ CallsignDb::loadFromFile) on
// synthetic Master.dta files, plus the callsign sources' fallbacks.

import Foundation
import MRCore
@testable import MRSimulation
import Testing

private let indexEntries = 37 * 37 + 1  // 1370
private let indexBytes = indexEntries * 4  // 5480

/// A Master.dta-shaped file: the 1370-entry little-endian Int32 header
/// (first = header size, last = file size unless overridden) followed by
/// `data`.
private func masterDta(_ data: [UInt8], first: Int32? = nil, last: Int32? = nil) -> Data {
    var header = [Int32](repeating: 0, count: indexEntries)
    header[0] = first ?? Int32(indexBytes)
    header[indexEntries - 1] = last ?? Int32(indexBytes + data.count)
    var out = Data()
    for v in header {
        withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
    }
    out.append(contentsOf: data)
    return out
}

/// NUL-terminated records.
private func records(_ calls: [String]) -> [UInt8] {
    calls.flatMap { Array($0.utf8) + [0] }
}

/// Writes `data` to a fresh temp file and returns its URL.
private func tempFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mr-calls-\(UUID().uuidString).dta")
    try data.write(to: url)
    return url
}

private func load(_ data: Data, into db: CallsignDb = CallsignDb()) throws -> (CallsignDb, Bool) {
    let url = try tempFile(data)
    defer { try? FileManager.default.removeItem(at: url) }
    let ok = db.load(from: url)
    return (db, ok)
}

/// Drains the database with pickAndRemoveCall; stops at the fallback.
private func drain(_ db: CallsignDb, seed: UInt64 = 1) -> [String] {
    let rng = Random(seed: seed)
    var out: [String] = []
    while db.count > 0 {
        out.append(db.pickAndRemoveCall(rng))
    }
    return out
}

@Suite struct CallsignDbTests {
    @Test func fileShorterThanHeaderIsRejected() throws {
        let short = Data(masterDta([]).prefix(indexBytes - 1))
        let (db, ok) = try load(short)
        #expect(!ok)
        #expect(db.count == 0)
    }

    @Test func badFirstSentinelIsRejected() throws {
        let (db, ok) = try load(masterDta(records(["W1AW"]), first: Int32(indexBytes - 4)))
        #expect(!ok)
        #expect(db.count == 0)
    }

    @Test func badLastSentinelIsRejected() throws {
        let data = records(["W1AW"])
        let (db, ok) = try load(masterDta(data, last: Int32(indexBytes + data.count + 1)))
        #expect(!ok)
        #expect(db.count == 0)
    }

    @Test func headerOnlyFileLoadsZeroCalls() throws {
        let (db, ok) = try load(masterDta([]))
        #expect(ok)
        #expect(db.count == 0)
        #expect(db.pickCall(Random(seed: 1)) == "P29SX")
        #expect(db.pickAndRemoveCall(Random(seed: 1)) == "P29SX")
    }

    @Test func duplicatesAndEmptyRecordsAreDropped() throws {
        // "\0\0" is an empty record; the C++ skips it.
        let data = records(["AA1A", "BB2B", "AA1A"]) + [0] + records(["CC3C", "BB2B"])
        let (db, ok) = try load(masterDta(data))
        #expect(ok)
        #expect(db.count == 3)
        #expect(Set(drain(db)) == ["AA1A", "BB2B", "CC3C"])
    }

    @Test func missingFinalNulStillYieldsLastCall() throws {
        let data = records(["AA1A"]) + Array("BB2B".utf8)
        let (db, ok) = try load(masterDta(data))
        #expect(ok)
        #expect(db.count == 2)
        #expect(Set(drain(db)) == ["AA1A", "BB2B"])
    }

    // The C++ dedups std::string bytes. Swift String equality would merge
    // canonically equivalent spellings and every invalid sequence (both
    // decode to U+FFFD); byte dedup keeps them apart.
    @Test func dedupComparesRawBytes() throws {
        let precomposed: [UInt8] = [0x41, 0xC3, 0xA9]  // "Aé"
        let decomposed: [UInt8] = [0x41, 0x65, 0xCC, 0x81]  // "Ae\u{301}"
        let data = precomposed + [0] + decomposed + [0] + [0xFF, 0] + [0xFE, 0] + [0xFF, 0]
        let (db, ok) = try load(masterDta(data))
        #expect(ok)
        #expect(db.count == 4)
    }

    @Test func failedLoadKeepsPreviousList() throws {
        let (db, ok) = try load(masterDta(records(["AA1A", "BB2B", "CC3C"])))
        #expect(ok)
        #expect(db.count == 3)
        let (_, ok2) = try load(masterDta(records(["DD4D"]), first: 0), into: db)
        #expect(!ok2)
        #expect(db.count == 3)
        #expect(!db.load(from: URL(fileURLWithPath: "/nonexistent/Master.dta")))
        #expect(db.count == 3)
    }

    @Test func drainingFallsBackToP29SX() throws {
        let (db, _) = try load(masterDta(records(["AA1A", "BB2B"])))
        let rng = Random(seed: 5)
        let picked = [db.pickAndRemoveCall(rng), db.pickAndRemoveCall(rng)]
        #expect(Set(picked) == ["AA1A", "BB2B"])
        #expect(db.count == 0)
        #expect(db.pickAndRemoveCall(rng) == "P29SX")
        #expect(db.pickCall(rng) == "P29SX")
    }

    @Test func pickCallDoesNotRemove() throws {
        let (db, _) = try load(masterDta(records(["AA1A", "BB2B"])))
        let rng = Random(seed: 5)
        for _ in 0..<10 {
            #expect(["AA1A", "BB2B"].contains(db.pickCall(rng)))
        }
        #expect(db.count == 2)
    }

    @Test func masterDtaHasTheExpectedCallCount() {
        let db = CallsignDb()
        #expect(db.load(from: masterDtaURL()))
        #expect(db.count == 32_668)
    }

    // HST tops the pile-up to Activity with pickAndRemoveCall; once the
    // database runs dry every further caller is the fallback "P29SX".
    @Test func hstWithActivityLargerThanDatabase() throws {
        let (db, _) = try load(masterDta(records(["AA1A", "BB2B"])))
        let c = Contest(calls: db, bufferSize: AudioK.defaultBufferSamples, random: Random(seed: 3))
        var s = ContestSettings()
        s.activity = 5
        s.qrm = false
        s.qrn = false
        c.setSettings(s)
        c.setRunMode(.hst)
        var buf = [Float](repeating: 0, count: AudioK.defaultBufferSamples)
        for _ in 0..<AudioK.startupSkipBlocks {
            c.renderNextBlock(&buf)
        }
        #expect(c.stations.dxCount == 5)
        #expect(db.count == 0)
        let calls = c.stations.map(\.myCall)
        #expect(calls.filter { $0 == "P29SX" }.count == 3)
        #expect(Set(calls.filter { $0 != "P29SX" }) == ["AA1A", "BB2B"])
    }
}

@Suite struct CallsignSourceTests {
    @Test func hardcodedPickAndRemoveIsAPlainPick() {
        let src = HardcodedCallsignSource()
        for seed: UInt64 in 1...20 {
            #expect(src.pickAndRemoveCall(Random(seed: seed)) == src.pickCall(Random(seed: seed)))
        }
    }
}
