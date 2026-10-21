// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal CallLst.pas port (C++ src/simulation/CallsignDb). Master.dta is
// a packed binary:
//   - 1370 * sizeof(int32) header — first entry equals header size in
//     bytes (5480), last entry equals total file size. The middle 1368
//     entries are offsets into the data block; we don't use them
//     because we just walk the whole null-terminated string section.
//   - data block: one null-terminated ASCII callsign per record.
// On load we dedup (Pascal also dedups via Sort+StrComp neighbour
// compare), keeping first-seen order, and stash the calls in an array.
//
// Threading: unlike the C++ (which guards the list with a mutex so it
// can load on its own thread), this class is not synchronized — the
// engine has no locks. Finish load(from:) before handing the database
// to a Contest (or to the simulation thread).

import Foundation
import MRCore

public final class CallsignDb: CallsignSource {
    // Pascal: INDEXSIZE = Sqr(37) + 1 = 1370; INDEXBYTES = 5480.
    private static let indexEntries = 37 * 37 + 1
    private static let indexBytes = indexEntries * 4

    private var calls: [String] = []

    public init() {}

    public var count: Int { calls.count }

    /// Parses the Master.dta file at `url`. Returns true on success; on
    /// failure the database stays as it was (empty if never loaded) and
    /// pickCall() falls back to the literal "P29SX" (Pascal parity).
    @discardableResult
    public func load(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            return false
        }
        let bytes = [UInt8](data)
        let fileSize = bytes.count
        if fileSize < Self.indexBytes {
            return false
        }
        func int32(at entry: Int) -> Int32 {
            let o = entry * 4
            let u = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8
                | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
            return Int32(bitPattern: u)
        }
        // Pascal checks the first and last entries match expected
        // sentinel values; we do the same.
        if Int(int32(at: 0)) != Self.indexBytes
            || Int(int32(at: Self.indexEntries - 1)) != fileSize {
            return false
        }

        // Dedup on the raw bytes, as the C++ unordered_set<std::string>
        // does. Comparing Swift Strings instead would merge canonically
        // equivalent Unicode spellings and every invalid sequence
        // (decoded to U+FFFD); Master.dta is pure ASCII, so the result
        // is the same there, but bytes are the specification.
        var picked: [String] = []
        picked.reserveCapacity(20000)  // Pascal's L.Capacity := 20000 hint
        var seen = Set<[UInt8]>(minimumCapacity: 20000)

        var i = Self.indexBytes
        while i < fileSize {
            let start = i
            while i < fileSize && bytes[i] != 0 {
                i += 1
            }
            if i > start {
                let call = Array(bytes[start..<i])
                if seen.insert(call).inserted {
                    picked.append(String(decoding: call, as: UTF8.self))
                }
            }
            i += 1  // skip the null (or step past the end without one)
        }
        calls = picked
        return true
    }

    public func pickCall(_ rng: Random) -> String {
        if calls.isEmpty {
            // Pascal CallLst.PickCall fallback.
            return "P29SX"
        }
        return calls[rng.uniformInt(calls.count)]
    }

    public func pickAndRemoveCall(_ rng: Random) -> String {
        if calls.isEmpty {
            return "P29SX"
        }
        let idx = rng.uniformInt(calls.count)
        let out = calls[idx]
        // Swap-pop: O(1) removal without preserving order (as the C++).
        calls[idx] = calls[calls.count - 1]
        calls.removeLast()
        return out
    }
}
