// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/ComplexBuf.h. Plain struct mirroring the Pascal
// `TReImArrays` record. Real and imaginary parts share equal length:
// every initializer and resize() keeps them equal, and the consumers that
// index both by one count (Modulator.modulate, PingPongFilter.process)
// check it. `re`/`im` stay plain stored arrays so the engine can fill
// them in place through withUnsafeMutableBufferPointer (no observers, no
// copies on the audio path); code that mutates them must not change
// either length on its own.
// Pre-allocated by the simulation engine to the maximum buffer size and
// reused; the hot path never grows it, so no allocations happen during
// audio rendering. Mutating functions take it `inout`, where the C++
// takes `ComplexBuf&`.

public struct ComplexBuf: Sendable, Equatable {
    public var re: [Float]
    public var im: [Float]

    public init() {
        re = []
        im = []
    }

    public init(count: Int) {
        re = [Float](repeating: 0, count: count)
        im = [Float](repeating: 0, count: count)
    }

    /// - Precondition: `re.count == im.count`.
    public init(re: [Float], im: [Float]) {
        precondition(re.count == im.count, "ComplexBuf: re and im lengths differ")
        self.re = re
        self.im = im
    }

    /// std::vector::resize semantics: keeps the existing prefix, new
    /// elements are zero.
    public mutating func resize(_ n: Int) {
        Self.resize(&re, n)
        Self.resize(&im, n)
    }

    public var size: Int { re.count }

    /// The equal-length invariant (re.count == im.count).
    public var isConsistent: Bool { re.count == im.count }

    /// Zeroes both channels (length unchanged).
    public mutating func clear() {
        for i in re.indices { re[i] = 0 }
        for i in im.indices { im[i] = 0 }
    }

    private static func resize(_ a: inout [Float], _ n: Int) {
        if n < a.count {
            a.removeLast(a.count - n)
        } else if n > a.count {
            a.append(contentsOf: repeatElement(0, count: n - a.count))
        }
    }
}
