// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Shared random source for the simulation. Port of the C++
// mr::core::Random: std::mt19937 (32-bit Mersenne Twister) plus the
// distribution helpers the original's RndFunc.pas provides. Every draw
// consumes the generator exactly as the C++ does, so a given seed gives
// the same contest in both implementations (verified against
// the frozen reference data in MRTestSupport).
//
// Not thread-safe: the simulation thread owns it.

import Darwin

/// `std::mt19937`: MT19937 with the standard 32-bit parameters.
/// Internal: the engine draws through `Random`.
struct MT19937: Sendable {
    private static let n = 624
    private static let m = 397
    private static let upperMask: UInt32 = 0x8000_0000
    private static let lowerMask: UInt32 = 0x7FFF_FFFF
    private static let matrixA: UInt32 = 0x9908_B0DF
    private var state = [UInt32](repeating: 0, count: 624)
    private var index = 624

    init(seed: UInt32) {
        state[0] = seed
        for i in 1..<Self.n {
            let prev = state[i - 1]
            state[i] = 1_812_433_253 &* (prev ^ (prev >> 30)) &+ UInt32(i)
        }
        index = Self.n
    }

    mutating func next() -> UInt32 {
        if index >= Self.n {
            twist()
        }
        var y = state[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C_5680
        y ^= (y << 15) & 0xEFC6_0000
        y ^= y >> 18
        return y
    }

    /// Regenerates all 624 words. Same recurrence as the textbook
    /// `state[(i + 1) % n]` / `state[(i + m) % n]` loop, with the modulo
    /// split out into three index ranges (as libc++ does): pure integer
    /// arithmetic on the same values in the same order, so the output is
    /// identical.
    private mutating func twist() {
        let n = Self.n
        let m = Self.m
        state.withUnsafeMutableBufferPointer { s in
            @inline(__always)
            func step(_ i: Int, _ next: Int, _ far: Int) {
                let y = (s[i] & Self.upperMask) | (s[next] & Self.lowerMask)
                var v = s[far] ^ (y >> 1)
                if y & 1 != 0 {
                    v ^= Self.matrixA
                }
                s[i] = v
            }
            for i in 0..<(n - m) {          // i + m < n
                step(i, i + 1, i + m)
            }
            for i in (n - m)..<(n - 1) {    // i + m wraps, i + 1 does not
                step(i, i + 1, i + m - n)
            }
            step(n - 1, 0, m - 1)           // both wrap
        }
        index = 0
    }
}

public final class Random {
    private var rng: MT19937
    public private(set) var seed: UInt64
    private var hasSparedNormal = false
    private var sparedNormal: Float = 0

    private static let tinyEpsilon: Float = 1.0e-12

    /// Seeded from the system entropy source, like the C++ default
    /// (std::random_device, two 32-bit draws). The full 64-bit value is
    /// kept in `seed` (for logging/reproduction); the generator uses its
    /// low 32 bits, as `std::mt19937::seed` does.
    public convenience init() {
        var g = SystemRandomNumberGenerator()
        self.init(seed: g.next())
    }

    public init(seed: UInt64) {
        self.seed = seed
        // std::mt19937::seed takes result_type: the seed is truncated
        // to its low 32 bits.
        rng = MT19937(seed: UInt32(truncatingIfNeeded: seed))
    }

    public func reseed(_ s: UInt64) {
        seed = s
        rng = MT19937(seed: UInt32(truncatingIfNeeded: s))
        hasSparedNormal = false
    }

    /// Raw 32-bit draw.
    public func nextUInt32() -> UInt32 { rng.next() }

    /// [0, 1) as `Float(u32) * 2^-32` (C++ uniform01). The conversion
    /// rounds to nearest, so values just below 2^32 can produce 1.0,
    /// exactly as in the C++.
    public func uniform01() -> Float {
        Float(rng.next()) * (1.0 / 4_294_967_296.0)
    }

    /// 0..<n, consuming draws exactly like libc++'s
    /// std::uniform_int_distribution<int>(0, n - 1) over mt19937: no draw
    /// for n == 1, otherwise rejection sampling of `draw & mask` where
    /// the mask covers the bit width of n - 1. n <= 0 returns 0 without
    /// drawing (C++ Random::uniformInt guard).
    ///
    /// - Precondition: `n <= UInt32.max` (the C++ takes an `int`; one
    ///   32-bit draw cannot cover a wider range).
    public func uniformInt(_ n: Int) -> Int {
        if n <= 0 {
            return 0
        }
        precondition(n <= Int(UInt32.max), "Random.uniformInt: n exceeds the 32-bit draw range")
        let rp = UInt32(n)
        if rp == 1 {
            return 0
        }
        var w = 32 - rp.leadingZeroBitCount - 1
        if rp & (UInt32.max >> (32 - w)) != 0 {
            w += 1
        }
        let mask: UInt32 = w >= 32 ? UInt32.max : (UInt32.max >> (32 - w))
        var u: UInt32
        repeat {
            u = rng.next() & mask
        } while u >= rp
        return Int(u)
    }

    /// Box-Muller with the second value of each pair cached.
    public func normal() -> Float {
        if hasSparedNormal {
            hasSparedNormal = false
            return sparedNormal
        }
        var u1 = uniform01()
        let u2 = uniform01()
        if u1 < Self.tinyEpsilon {
            u1 = Self.tinyEpsilon
        }
        let radius = (-2.0 * log(u1)).squareRoot()
        let angle = Float(MathK.twoPi) * u2
        let sc = sinCos(angle)  // C++ std::sin/std::cos pair → sincos
        sparedNormal = radius * sc.sin
        hasSparedNormal = true
        return radius * sc.cos
    }

    /// Pascal RndGaussLim: mean + N(0,1)·lim/2, clamped to mean ± lim.
    public func gaussLim(_ mean: Float, _ lim: Float) -> Float {
        let candidate = mean + normal() * 0.5 * lim
        // std::clamp(v, lo, hi)
        let lo = mean - lim
        let hi = mean + lim
        if candidate < lo { return lo }
        if hi < candidate { return hi }
        return candidate
    }

    /// Pascal RndRayleigh.
    public func rayleigh(_ mean: Float) -> Float {
        var u1 = uniform01()
        var u2 = uniform01()
        if u1 < Self.tinyEpsilon { u1 = Self.tinyEpsilon }
        if u2 < Self.tinyEpsilon { u2 = Self.tinyEpsilon }
        return mean * (-log(u1) - log(u2)).squareRoot()
    }

    /// Knuth's product method (C++ Random::poisson).
    public func poisson(_ mean: Float) -> Int {
        if mean <= 0 {
            return 0
        }
        let threshold = exp(-mean)
        var product: Float = 1.0
        var k = 0
        while true {
            product *= uniform01()
            if product < threshold {
                return k
            }
            k += 1
            if k > 1024 {
                return k
            }
        }
    }

    /// Pascal RndUShaped: sin(π·(u − ½)).
    public func uShaped() -> Float {
        let u = uniform01()
        return sin(Float(MathK.pi) * (u - 0.5))
    }
}
