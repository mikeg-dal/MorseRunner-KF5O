// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// TMainForm.Run: which controls and menu items a run mode enables, what
// WPX / HST force, and what starting a run resets.

import Foundation
import MRSimulation

/// Panel4's font colour.
public enum ModeColor: Sendable, Equatable {
    case red, green
}

/// Where AlWavFile1 stands after Run.
public enum RecordingChange: Sendable, Equatable {
    /// Run(rmStop): close the file if open.
    case close
    /// Run(<mode>): (re)open MorseRunner.wav for writing if SaveWav.
    case openIfEnabled
}

public struct RunControls: Sendable, Equatable {
    public var mode: RunMode
    /// Edit4 / Settings › Call…
    public var myCallEnabled: Bool
    /// SpinEdit2 / Settings › Duration.
    public var durationEnabled: Bool
    /// ToolButton1.Down.
    public var runButtonDown: Bool
    /// CheckBox2..6 and Settings › QRN..LIDS.
    public var conditionsEnabled: Bool
    /// WPX checks all five, HST clears them; nil leaves them.
    public var forcedConditions: Bool?
    /// WPX / HST: SpinEdit2.Value := CompDuration.
    public var forcedDuration: Int?
    /// Pile-Up..HST items in both menus.
    public var runItemsEnabled: Bool
    /// Stop in both menus.
    public var stopEnabled: Bool
    /// SpinEdit3 / Settings › Activity, ComboBox2 / CW Bandwidth.
    public var activityEnabled: Bool
    public var bandwidthEnabled: Bool
    /// HST: SpinEdit3.Value := 4; SetBw(10).
    public var forcedActivity: Int?
    public var forcedBandwidthIndex: Int?
    /// ListView1.Visible: HST hides it, other runs show it, Stop leaves it.
    public var scoreTableVisible: Bool?
    /// Panel4.
    public var caption: String
    public var captionColor: ModeColor
    /// Not Stop: AbortSend, BlockNumber 0, Nr 1, Log.Clear, WipeBoxes,
    /// RichEdit1 visible, IncRit(0).
    public var resetsSession: Bool
    public var recording: RecordingChange
}

public enum RunModeRules {
    /// HST: SpinEdit3.Value := 4.
    public static let hstActivity = 4

    /// Run's Title array.
    public static func title(_ mode: RunMode) -> String {
        switch mode {
        case .stop: ""
        case .pileUp: "Pile-Up"
        case .single: "Single Calls"
        case .wpx: "COMPETITION"
        case .hst: "H S T"
        }
    }

    /// `if Value = Ini.RunMode then Exit`.
    public static func shouldRun(_ requested: RunMode, current: RunMode) -> Bool {
        requested != current
    }

    public static func isCompetition(_ mode: RunMode) -> Bool { mode == .wpx || mode == .hst }

    public static func controls(for mode: RunMode, competitionDuration: Int) -> RunControls {
        let stop = mode == .stop
        let compet = isCompetition(mode)
        let hst = mode == .hst
        return RunControls(
            mode: mode,
            myCallEnabled: stop,
            durationEnabled: stop,
            runButtonDown: !stop,
            conditionsEnabled: !compet,
            forcedConditions: mode == .wpx ? true : (hst ? false : nil),
            forcedDuration: compet ? competitionDuration : nil,
            runItemsEnabled: stop,
            stopEnabled: !stop,
            activityEnabled: !hst,
            bandwidthEnabled: !hst,
            forcedActivity: hst ? hstActivity : nil,
            forcedBandwidthIndex: hst ? BandwidthTable.hstIndex : nil,
            scoreTableVisible: hst ? false : (stop ? nil : true),
            caption: title(mode),
            captionColor: compet ? .red : .green,
            resetsSession: !stop,
            recording: stop ? .close : .openIfEnabled)
    }
}
