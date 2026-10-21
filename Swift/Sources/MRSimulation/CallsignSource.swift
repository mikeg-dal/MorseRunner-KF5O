// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pluggable callsign generator used by Contest to spawn DxStation and
// QrmStation instances (C++ src/simulation/CallsignSource). CallsignDb
// is the real Master.dta-backed implementation; HardcodedCallsignSource
// is a small built-in generator for tests and for running without the
// database.
//
// HST mode wants `pickAndRemoveCall` so the same callsign never shows
// twice in a session; sources without removal treat it as a regular pick.

import MRCore

public protocol CallsignSource: AnyObject {
    /// Returns a random callsign for a fresh DX/QRM station.
    func pickCall(_ rng: Random) -> String
    /// HST-only: consume the picked call so it never recurs in this
    /// session. Default: pickCall.
    func pickAndRemoveCall(_ rng: Random) -> String
}

extension CallsignSource {
    public func pickAndRemoveCall(_ rng: Random) -> String { pickCall(rng) }
}

/// A small built-in generator (C++ HardcodedCallsignSource).
public final class HardcodedCallsignSource: CallsignSource {
    // Curated prefixes drawn from common DX entities. A digit 0..9 is
    // appended (no entry carries its own digit), then a 2- or 3-letter
    // suffix.
    private static let prefixes: [String] = [
        // North America — heavy US/Canada weighting matches contest activity
        "K", "N", "W", "AA", "AB", "AC", "AD", "AE",
        "AF", "AG", "AI", "AK", "KA", "KB", "KC", "KE",
        "KF", "KG", "KK", "NA", "NB", "NC", "NE", "NF",
        "NN", "WA", "WB", "WD", "WE", "WF", "WG", "WW",
        "VE", "VA", "VY",
        // Europe
        "DL", "DJ", "DK", "DF", "DG", "DH", "DM", "G",
        "M", "GM", "GW", "F", "EA", "EI", "I", "OK",
        "OZ", "SM", "PA", "ON",
        // Asia / Pacific / South America
        "JA", "JE", "BA", "VK", "ZL", "PY", "LU",
    ]
    private static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)

    public init() {}

    public func pickCall(_ rng: Random) -> String {
        var out = Self.prefixes[rng.uniformInt(Self.prefixes.count)].bytes
        out.append(UInt8(ascii: "0") + UInt8(rng.uniformInt(10)))
        // 70% chance of 2-letter suffix, 30% chance of 3-letter.
        let suffixLen = rng.uniform01() < 0.7 ? 2 : 3
        for _ in 0..<suffixLen {
            out.append(Self.letters[rng.uniformInt(26)])
        }
        return out.asString
    }
}
