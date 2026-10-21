// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Delphi's `System.Round`: exact halves go to the nearest even integer
/// (banker's rounding), unlike C's `lround`. Example: Round(24.5) = 24.
/// Every Pascal `Round` in the original maps to this.
///
/// - Precondition: `x` is finite and its rounded value fits in an `Int`.
///   Delphi raises EInvalidOp and the C++ conversion is undefined
///   behaviour there, so a caller passing NaN, ±infinity or a huge value
///   has a bug of its own; this traps with a clear message instead of
///   inventing a result.
@inlinable
public func delphiRound(_ x: Double) -> Int {
    let r = x.rounded(.toNearestOrEven)
    // -2^63 is exact in Double; 2^63 is the first value past Int.max.
    precondition(r >= -9_223_372_036_854_775_808.0 && r < 9_223_372_036_854_775_808.0,
                 "delphiRound: \(x) is not finite or does not fit in an Int")
    return Int(r)
}

/// `delphiRound(Double(x))`: the Float is widened exactly, so the result
/// is the Delphi rounding of the Float's value.
@inlinable
public func delphiRound(_ x: Float) -> Int {
    delphiRound(Double(x))
}
