// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Loads the frozen reference data produced by the former C++
// implementation (tools/golden at git tag cpp-qt-reference; see
// Swift/PORTING.md). Float arrays are raw
// little-endian Float32; structured data is JSON.

import Foundation

public enum Fixtures {
    public enum FixtureError: Error, CustomStringConvertible {
        /// A raw Float32 file whose size is not a multiple of 4 bytes.
        case partialFloat(path: String, byteCount: Int)

        public var description: String {
            switch self {
            case let .partialFloat(path, byteCount):
                "\(path): \(byteCount) bytes is not a whole number of Float32 values"
            }
        }
    }

    /// Root of the bundled fixture tree.
    public static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    public static func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }

    /// Raw little-endian Float32 values. Reads unaligned (Data gives no
    /// alignment guarantee) and byte-swaps on a big-endian host; a
    /// trailing partial value is an error, not silently dropped.
    public static func floats(_ relativePath: String) throws -> [Float] {
        try floats(littleEndian: data(relativePath), path: relativePath)
    }

    /// floats(_:) over bytes already in memory; `path` only labels errors.
    public static func floats(littleEndian d: Data, path: String = "<data>") throws -> [Float] {
        let size = MemoryLayout<UInt32>.size
        guard d.count % size == 0 else {
            throw FixtureError.partialFloat(path: path, byteCount: d.count)
        }
        let n = d.count / size
        return d.withUnsafeBytes { raw in
            [Float](unsafeUninitializedCapacity: n) { out, initialized in
                for i in 0..<n {
                    let bits = raw.loadUnaligned(fromByteOffset: i * size, as: UInt32.self)
                    out[i] = Float(bitPattern: UInt32(littleEndian: bits))
                }
                initialized = n
            }
        }
    }

    public static func json<T: Decodable>(_ type: T.Type, _ relativePath: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(relativePath))
    }

    /// Largest absolute difference between two float arrays (∞ when the
    /// lengths differ).
    public static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        var m: Float = 0
        for i in a.indices {
            m = max(m, abs(a[i] - b[i]))
        }
        return m
    }
}
