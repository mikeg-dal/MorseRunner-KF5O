// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of the data side of Log.pas: the QSO list, SaveQso's bookkeeping,
// CheckErr, UpdateStats / UpdateStatsHst, ShowRate and PaintHisto's bins.
// No UI or simulation dependency so it can be unit-tested and owned by
// the GUI thread (where Pascal's Log unit lived).
//
// The one piece of Log.pas this type does not do itself is the truth
// lookup: Pascal reaches into Tst.Stations for a finished DX station with
// the same call (DataToLastQso). In the port that lookup runs on the sim
// thread, which reports back; the GUI then calls applyTruth().
//
// String comparisons (dupe check, applyTruth, distinct prefixes) are on
// UTF-8 bytes, matching std::string ==, not Swift's canonical-equivalence
// String ==.

import MRCore

public struct Qso: Equatable, Sendable {
    public var t: Double = 0          // contest time, seconds since Run (Pascal: T)
    public var call = ""              // as logged, '?' stripped
    public var trueCall = ""          // filled from the DX station's own record
    public var rst = 0
    public var trueRst = 0
    public var nr = 0
    public var trueNr = 0
    public var pfx = ""               // WPX prefix, or the CallToScore value in HST
    public var dupe = false
    public var err = "NIL"            // "   " clean, else NIL / DUP / RST / "NR "

    public init() {}
}

public struct ScoreRow: Equatable, Sendable {
    public var pts = 0
    public var mul = 0
    public var score = 0

    public init(pts: Int = 0, mul: Int = 0, score: Int = 0) {
        self.pts = pts
        self.mul = mul
        self.score = score
    }
}

public struct Stats: Equatable, Sendable {
    public var raw = ScoreRow()
    public var verified = ScoreRow()

    public init() {}
}

private let clean = "   "

@inline(__always)
private func bytesEqual(_ a: String, _ b: String) -> Bool {
    a.utf8.elementsEqual(b.utf8)
}

public struct QsoLog: Sendable {
    /// Log.pas PaintHisto: 48 bars of 5 minutes (the 240-minute maximum
    /// contest length).
    public static let histogramBins = 48
    public static let histogramBinMinutes = 5
    /// Largest |t| add() accepts (about 31 700 years): keeps every time
    /// conversion in histogram() and formatRow() inside Int range.
    public static let maxAbsTime: Double = 1.0e12

    public private(set) var qsos: [Qso] = []

    public init() {}

    public var isEmpty: Bool { qsos.isEmpty }

    /// Log.pas SaveQso guard: call at least 3 chars, RST exactly 3, NR
    /// not empty. Pascal beeps and refuses to log otherwise. Lengths are
    /// byte counts, as in the C++.
    public static func entryIsValid(call: String, rst: String, nr: String) -> Bool {
        call.utf8.count >= 3 && rst.utf8.count == 3 && !nr.isEmpty
    }

    /// Log.pas Clear.
    public mutating func clear() {
        qsos.removeAll()
    }

    /// Log.pas SaveQso (minus the DX lookup, see the file comment).
    /// Strips '?' from the call, computes the prefix, marks a dupe when an
    /// earlier *clean* QSO has the same call, and runs CheckErr. With no
    /// truth yet the new entry is NIL until applyTruth() fills it.
    ///
    /// - Precondition: `tSeconds` is finite and |tSeconds| <= maxAbsTime.
    ///   (The C++ converts it to integers unchecked — undefined behaviour
    ///   for NaN/∞; contest times are a few hours at most.)
    @discardableResult
    public mutating func add(t tSeconds: Double, call callAsTyped: String, rst: Int,
                             nr: Int, hstMode: Bool) -> Qso {
        precondition(tSeconds.isFinite && abs(tSeconds) <= Self.maxAbsTime,
                     "QsoLog.add: time \(tSeconds) is not a finite contest time")
        var q = Qso()
        q.t = tSeconds
        q.call = String(decoding: callAsTyped.utf8.filter { $0 != UInt8(ascii: "?") },
                        as: UTF8.self)
        q.rst = rst
        q.nr = nr
        q.pfx = hstMode ? String(callToScore(q.call)) : extractPrefix(q.call)

        // Pascal: dupe only against an earlier QSO with the same call that
        // was itself clean (Err = '   ').
        q.dupe = qsos.contains { bytesEqual($0.call, q.call) && $0.err == clean }

        qsos.append(q)
        checkErrLast()
        return qsos[qsos.count - 1]
    }

    /// TDxStation.DataToLastQso + CheckErr. Applies only when `call`
    /// matches the most recent entry (Pascal compares MyCall to the last
    /// QSO's call). Returns true when the last entry changed.
    @discardableResult
    public mutating func applyTruth(call: String, trueRst: Int, trueNr: Int) -> Bool {
        guard let last = qsos.last, bytesEqual(last.call, call) else {
            return false
        }
        let i = qsos.count - 1
        qsos[i].trueCall = call
        qsos[i].trueRst = trueRst
        qsos[i].trueNr = trueNr
        checkErrLast()
        return true
    }

    private mutating func checkErrLast() {
        // Log.pas CheckErr — order matters: NIL beats DUP beats RST beats NR.
        let i = qsos.count - 1
        let q = qsos[i]
        if q.trueCall.isEmpty {
            qsos[i].err = "NIL"
        } else if q.dupe {
            qsos[i].err = "DUP"
        } else if q.trueRst != q.rst {
            qsos[i].err = "RST"
        } else if q.trueNr != q.nr {
            qsos[i].err = "NR "
        } else {
            qsos[i].err = clean
        }
    }

    /// Log.pas UpdateStats (WPX-style) or UpdateStatsHst. Pascal
    /// recomputes from the whole list: Raw counts every entry (dupes and
    /// NILs included) and an empty prefix still counts as a multiplier.
    public func stats(hstMode: Bool) -> Stats {
        var s = Stats()
        if hstMode {
            // UpdateStatsHst: Score = sum of CallToScore; Pts/Mul unused.
            for q in qsos {
                let pts = callToScore(q.call)
                s.raw.score += pts
                if q.err == clean {
                    s.verified.score += pts
                }
            }
            return s
        }

        // UpdateStats: PfxList is a sorted, dupIgnore string list, so the
        // multiplier is the number of distinct prefixes (empty included).
        var rawPfx = Set<[UInt8]>()
        var verPfx = Set<[UInt8]>()
        for q in qsos {
            s.raw.pts += 1
            rawPfx.insert(Array(q.pfx.utf8))
            if q.err == clean {
                s.verified.pts += 1
                verPfx.insert(Array(q.pfx.utf8))
            }
        }
        s.raw.mul = rawPfx.count
        s.raw.score = s.raw.pts * s.raw.mul
        s.verified.mul = verPfx.count
        s.verified.score = s.verified.pts * s.verified.mul
        return s
    }

    /// Log.pas ShowRate: QSOs in the last min(5 min, elapsed), scaled to
    /// an hourly rate. nil when no time has elapsed (Pascal exits and
    /// leaves the label untouched).
    public func rate(now nowSeconds: Double) -> Int? {
        if nowSeconds <= 0.0 {
            return nil
        }
        let window = min(5.0 * 60.0, nowSeconds)
        var cnt = 0
        for q in qsos.reversed() {
            if q.t > nowSeconds - window {
                cnt += 1
            } else {
                break
            }
        }
        return delphiRound(Double(cnt) / window * 3600.0)
    }

    /// Log.pas PaintHisto bins: QSOs per 5-minute block.
    public func histogram() -> [Int] {
        var bins = [Int](repeating: 0, count: Self.histogramBins)
        for q in qsos {
            // Pascal: Trunc(T * 1440) div 5. Clamp: a QSO logged exactly at
            // the 240-minute limit would index past the 48-bin array.
            let minute = Int(q.t / 60.0)
            let bin = min(max(minute / Self.histogramBinMinutes, 0), Self.histogramBins - 1)
            bins[bin] += 1
        }
        return bins
    }

    /// Log.pas LastQsoToScreen for entry `index`. The Sent NR column is
    /// RichEdit1.Lines.Count in Pascal, i.e. the entry's 1-based position
    /// (header line + earlier rows). The last 3 characters are the error
    /// tag, which the log view colours red.
    ///
    /// - Precondition: `qsos.indices.contains(index)` (the C++ uses
    ///   `qsos_.at(index)`, which throws).
    public func formatRow(_ index: Int, sentRst: Int) -> String {
        precondition(qsos.indices.contains(index), "QsoLog.formatRow: index \(index) out of range")
        let q = qsos[index]
        // FormatDateTime(' hh:nn:ss  ', T): DecodeTime rounds to the
        // millisecond, then the seconds field drops the remainder.
        // (C++ std::llround = round half away from zero.)
        let totalMs = Int64((q.t * 1000.0).rounded(.toNearestOrAwayFromZero))
        let totalSec = totalMs / 1000
        let hh = Int((totalSec / 3600) % 24)
        let mm = Int((totalSec / 60) % 60)
        let ss = Int(totalSec % 60)

        // Format('%-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s', ...). Delphi pads
        // but never truncates, same as printf.
        let sentNr = index + 1
        var out: [UInt8] = []
        out += Array(" ".utf8)
        out += zeroWidth(hh, 2) + Array(":".utf8) + zeroWidth(mm, 2) + Array(":".utf8)
            + zeroWidth(ss, 2)
        out += Array("  ".utf8) + leftJustify(q.call, 12)
        out += Array("  ".utf8) + precision(q.rst, 3) + Array(" ".utf8) + precision(q.nr, 4)
        out += Array("  ".utf8) + precision(sentRst, 3) + Array(" ".utf8)
            + precision(sentNr, 4)
        out += Array("  ".utf8) + leftJustify(q.pfx, 5)
        out += Array("  ".utf8) + leftJustify(q.err, 3)
        // The C++ formats into a 160-byte snprintf buffer.
        if out.count > 159 {
            out.removeLast(out.count - 159)
        }
        return String(decoding: out, as: UTF8.self)
    }
}

// printf "%-Ns": pad on the right with spaces to N bytes, never truncate.
private func leftJustify(_ s: String, _ width: Int) -> [UInt8] {
    var b = Array(s.utf8)
    if b.count < width {
        b += [UInt8](repeating: 32, count: width - b.count)
    }
    return b
}

// printf "%0Nd": field width N including the sign, zero-filled after it.
private func zeroWidth(_ v: Int, _ width: Int) -> [UInt8] {
    let digits = Array(String(v.magnitude).utf8)
    let sign: [UInt8] = v < 0 ? [UInt8(ascii: "-")] : []
    let pad = max(0, width - sign.count - digits.count)
    return sign + [UInt8](repeating: 48, count: pad) + digits
}

// printf "%.Nd": at least N digits, sign not counted.
private func precision(_ v: Int, _ digitsMin: Int) -> [UInt8] {
    let digits = Array(String(v.magnitude).utf8)
    let sign: [UInt8] = v < 0 ? [UInt8(ascii: "-")] : []
    let pad = max(0, digitsMin - digits.count)
    return sign + [UInt8](repeating: 48, count: pad) + digits
}
