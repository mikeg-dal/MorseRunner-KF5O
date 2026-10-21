// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Darwin

/// sin and cos of the same angle in one libm call (Apple's
/// `__sincos_stret`). Clang merges a C++ `std::sin(x)` / `std::cos(x)`
/// pair into this call, and its results can differ from separate
/// `sin`/`cos` calls in the last bit. The port uses it exactly where the
/// C++ computes both of the same angle, so the output matches the C++
/// reference data bit for bit.
@inlinable
public func sinCos(_ x: Float) -> (sin: Float, cos: Float) {
    let r = __sincosf_stret(x)
    return (r.__sinval, r.__cosval)
}

@inlinable
public func sinCos(_ x: Double) -> (sin: Double, cos: Double) {
    let r = __sincos_stret(x)
    return (r.__sinval, r.__cosval)
}
