// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The end of a session (Contest.pas GetAudio): HST always pops its score
// (even when the user stopped it), WPX only when the time ran out, the
// other modes nothing. Plus PopupScoreHst's / PopupScoreWpx's lines.
//
// Dates: FormatDateTime on Now — local wall-clock time, Gregorian
// digits, whatever the user's locale or calendar. They go into the
// CRC-stamped score line, so they must not follow the system locale.

import Foundation
import MRScoring
import MRSimulation

public enum ContestEndOutcome: Sendable, Equatable {
    case none
    /// PopupScoreHst: append `line` to HstResults.txt, ShowMessage(`message`).
    case hst(line: String, message: String)
    /// PopupScoreWpx: append `line` to the score list, show the score
    /// dialog (with the banner when `newRecord`), HiScore := `hiScore`.
    case wpx(line: String, score: Int, newRecord: Bool, hiScore: Int)
}

public enum ContestEndPolicy {
    public static func outcome(mode: RunMode, stoppedByUser: Bool, table: ScoreTableModel,
                               call: String, hamName: String, hiScore: Int,
                               now: Date, timeZone: TimeZone) -> ContestEndOutcome {
        let call = call.trimmingCharacters(in: .whitespaces)  // Ini.Call is SetMyCall(Trim(...))
        switch mode {
        case .hst:
            let line = hstLine(now: now, timeZone: timeZone, call: call, hamName: hamName,
                               score: table.hstCaption)
            return .hst(line: line, message: "HST Score: \(table.verifiedScore)")
        case .wpx where !stoppedByUser:
            let line = wpxLine(now: now, timeZone: timeZone, call: call,
                               pts: table.verifiedPts, mul: table.verifiedMul)
            // StrToIntDef(ListView1.Items[2].SubItems[1], 0).
            let score = Int(table.verifiedScore) ?? 0
            return .wpx(line: line, score: score, newRecord: score > hiScore,
                        hiScore: max(hiScore, score))
        default:
            return .none
        }
    }

    /// Format('%s'#9'%s'#9'%s'#9'%s', [FormatDateTime('yyyy-mm-dd hh:nn',
    /// Now), Ini.Call, Ini.HamName, Panel11.Caption]).
    public static func hstLine(now: Date, timeZone: TimeZone, call: String, hamName: String,
                               score: String) -> String {
        "\(date(now, timeZone)) \(time(now, timeZone))\t\(call)\t\(hamName)\t\(score)"
    }

    /// Format('%s %s %s %s ', [FormatDateTime('yyyy-mm-dd', Now), Ini.Call,
    /// verified Pts, verified Mult]) + '[' + IntToHex(CRC32, 8) + ']'.
    public static func wpxLine(now: Date, timeZone: TimeZone, call: String,
                               pts: String, mul: String) -> String {
        stampScoreLine("\(date(now, timeZone)) \(call) \(pts) \(mul) ")
    }

    private static func components(_ d: Date, _ tz: TimeZone) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    }

    /// yyyy-mm-dd.
    static func date(_ d: Date, _ tz: TimeZone) -> String {
        let c = components(d, tz)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// hh:nn.
    static func time(_ d: Date, _ tz: TimeZone) -> String {
        let c = components(d, tz)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
