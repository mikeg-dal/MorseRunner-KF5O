// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxOper.pas::IsMyCall (C++ src/simulation/IsMyCall): weighted
// Levenshtein between what the player keyed and the DX's own call, with
// '?' wildcards and the Pascal post-classification corrections.

import MRCore

public enum CallMatch: Int, Sendable {
    case no = 0, almost, yes
}

public struct IsMyCallOptions: Sendable {
    /// The DX station's true callsign (what the FSM is verifying against).
    public var mine: String
    /// What the player keyed. May contain '?' as a wildcard.
    public var his: String
    /// LID mode: small probability of mishearing Yes↔Almost; when false,
    /// the rule for length-2 heard calls is tightened.
    public var lidsMode: Bool

    public init(mine: String, his: String, lidsMode: Bool = false) {
        self.mine = mine
        self.his = his
        self.lidsMode = lidsMode
    }
}

public func isMyCall(_ opts: IsMyCallOptions, _ rng: Random) -> CallMatch {
    let mine = opts.mine.bytes
    let his = opts.his.bytes
    let q = UInt8(ascii: "?")

    // DP matrix `M` is (|his|+1) × (|mine|+1). M[x][y] is the minimum
    // edit cost transforming `his[0..x)` into a prefix of `mine[0..y)`.
    // Pascal indexing is 1-based; we shift to 0-based, but keep the
    // same recurrence shape.
    let hN = his.count
    let mN = mine.count
    var matrix = [[Int]](repeating: [Int](repeating: 0, count: mN + 1), count: hN + 1)

    // Pascal: M[x,0] := M[x-1,0] + W_X (insertion cost). M[0,y] = 0
    // (free skips on `mine`).
    if hN >= 1 {
        for x in 1...hN {
            matrix[x][0] = matrix[x - 1][0] + SimK.levInsCost
        }
    }

    if hN >= 1 && mN >= 1 {
        for x in 1...hN {
            for y in 1...mN {
                let c = his[x - 1]    // heard character (may be '?')
                let c0 = mine[y - 1]  // true character

                // Pascal: T := M[x, y-1]; if (x < High) and (C[x] <> '?') then Inc(T, W_Y);
                var t = matrix[x][y - 1]
                if x < hN && c != q {
                    t += SimK.levDelCost
                }
                // Pascal: L := M[x-1, y]; if (C[x] <> '?') then Inc(L, W_X).
                var l = matrix[x - 1][y]
                if c != q {
                    l += SimK.levInsCost
                }
                // Pascal: D := M[x-1, y-1]; if not (C[x] in [C0[y], '?']) then Inc(D, W_D).
                var d = matrix[x - 1][y - 1]
                if c != q && c != c0 {
                    d += SimK.levSubstCost
                }
                matrix[x][y] = min(t, d, l)
            }
        }
    }

    let penalty = matrix[hN][mN]

    var result: CallMatch
    if penalty == 0 {
        result = .yes
    } else if penalty <= SimK.levMatchThresh {
        result = .almost
    } else {
        result = .no
    }

    // Pascal post-classification corrections:

    // 1) LIDs off and the heard string is exactly 2 chars: Almost → No.
    if !opts.lidsMode && his.count == 2 && result == .almost {
        result = .no
    }

    // 2) A zero-penalty result from length mismatch or wildcards is a
    //    partial copy: Almost.
    if result == .yes {
        if his.count != mine.count || his.contains(q) {
            result = .almost
        }
    }

    // 3) Fewer than 2 non-wildcard characters: no match.
    if his.filter({ $0 != q }).count < 2 {
        result = .no
    }

    // 4) LID mishearing: random Yes→Almost or Almost→Yes flips, only for
    //    heard calls longer than 3.
    if opts.lidsMode && his.count > 3 {
        if result == .yes {
            if rng.uniform01() < SimK.mishearStandardProb {
                result = .almost
            }
        } else if result == .almost {
            if rng.uniform01() < SimK.mishearLidProb {
                result = .yes
            }
        }
    }

    return result
}
