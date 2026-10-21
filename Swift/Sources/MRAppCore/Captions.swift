// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Text and geometry the window shows: Panel2 (clock), Panel7 (rate),
// Panel4 (pile-up count), ListView1 + Panel11 (score table), PaintBox1
// (histogram) and RichEdit1 (log rows, headers, View Score Table).

import Foundation
import MRScoring
import MRSimulation

public enum Captions {
    /// Panel2: FormatDateTime('hh:nn:ss', Seconds/86400). DecodeTime
    /// rounds to the millisecond; the hour wraps at 24.
    public static func clock(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00:00" }
        let total = Int64((seconds * 1000).rounded(.toNearestOrAwayFromZero)) / 1000
        return String(format: "%02d:%02d:%02d", Int((total / 3600) % 24),
                      Int((total / 60) % 60), Int(total % 60))
    }

    /// Panel7: Format('%d  qso/hr.', ...).
    public static func rate(_ qsoPerHour: Int) -> String { "\(qsoPerHour)  qso/hr." }

    /// Panel4 in Pile-Up: Format('Pile-Up:  %d', [DxCount]).
    public static func pileUp(_ count: Int) -> String { "Pile-Up:  \(count)" }

    /// Log.Clear's header line (underlined, clBlue).
    public static func logHeader(hst: Bool) -> String {
        hst ? " UTC       Call          Recv      Sent      Score  Chk"
            : " UTC       Call          Recv      Sent      Pref   Chk"
    }

    /// LastQsoToScreen colours the last 3 characters (the error tag) red.
    public static func splitLogRow(_ row: String) -> (body: String, tag: String) {
        (String(row.dropLast(3)), String(row.suffix(3)))
    }

    /// ViewScoreTable1Click: the score list, or the empty message when
    /// the file does not exist. (An existing empty file shows nothing,
    /// as RichEdit1.Lines.LoadFromFile does.)
    public static let emptyScoreTable = "Your score table is empty"

    public static func scoreTableText(fileContents: String?) -> String {
        guard let fileContents else { return emptyScoreTable }
        var s = Substring(fileContents)
        while s.last == "\n" || s.last == "\r" || s.last == "\r\n" { s = s.dropLast() }
        return String(s)
    }

    /// The window caption: 'Morse Runner' (+ ':  ' + HamName).
    public static func windowTitle(hamName: String) -> String {
        hamName.isEmpty ? "Morse Runner" : "Morse Runner:  \(hamName)"
    }
}

/// ListView1 (Pts / Mult / Score × Raw / Verified) and Panel11's caption,
/// which shows the score in HST.
public struct ScoreTableModel: Sendable, Equatable {
    public static let rowTitles = ["Pts", "Mult", "Score"]
    public static let columnTitles = ["", "Raw", "Verified"]

    /// cells[row][col], col 0 = Raw, 1 = Verified.
    public private(set) var cells: [[String]] = [["0", "0"], ["0", "0"], ["0", "0"]]
    public private(set) var hstCaption = "0"

    public init() {}

    /// Log.Clear: '' for Pts/Mult in HST, '0' otherwise; Score '0'.
    /// Pascal leaves Panel11's caption at the last run's score until the
    /// first QSO; the port resets it to '0' too (parity-checklist ◑).
    public mutating func reset(hst: Bool) {
        let empty = hst ? "" : "0"
        cells = [[empty, empty], [empty, empty], ["0", "0"]]
        hstCaption = "0"
    }

    /// UpdateStats / UpdateStatsHst.
    public mutating func update(_ st: Stats, hst: Bool) {
        if hst {
            cells = [["", ""], ["", ""], ["\(st.raw.score)", "\(st.verified.score)"]]
            hstCaption = "\(st.verified.score)"
        } else {
            cells = [["\(st.raw.pts)", "\(st.verified.pts)"],
                     ["\(st.raw.mul)", "\(st.verified.mul)"],
                     ["\(st.raw.score)", "\(st.verified.score)"]]
        }
    }

    /// ListView1.Items[r].SubItems[1].
    public var verifiedPts: String { cells[0][1] }
    public var verifiedMul: String { cells[1][1] }
    public var verifiedScore: String { cells[2][1] }
}

/// PaintHisto's bars: x = i·4 + 1, y = Height − 3 − n·2, FillRect up to
/// Height − 2 (right / bottom exclusive). Empty bins draw a 1-px stub.
public enum HistogramGeometry {
    public static var binCount: Int { QsoLog.histogramBins }

    public static func bar(index i: Int, count n: Int, height: Int)
        -> (x: Int, y: Int, width: Int, height: Int) {
        let x = i * 4 + 1
        let y = height - 3 - n * 2
        return (x, y, 3, (height - 2) - y)
    }

    public static func bars(_ bins: [Int], height: Int) -> [(x: Int, y: Int, width: Int, height: Int)] {
        bins.enumerated().map { bar(index: $0.offset, count: $0.element, height: height) }
    }

    public static var emptyBins: [Int] { Array(repeating: 0, count: binCount) }
}
