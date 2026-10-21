// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The station controls' value tables and steppers: ComboBox1 (pitch),
// ComboBox2 (bandwidth), the speed keys, the spin edits and the RIT.

import Foundation

/// ComboBox1 / Settings › CW Pitch: SetPitch, Ini.Pitch := 300 + No·50.
public enum PitchTable {
    public static let count = 13
    /// Ini.pas default ReadInteger(..., 'Pitch', 3) = 450 Hz.
    public static let defaultIndex = 3

    public static func hz(index: Int) -> Int { 300 + index * 50 }

    /// The combo index showing exactly `hz`, or nil.
    public static func index(hz: Int) -> Int? {
        let d = hz - 300
        guard d >= 0, d % 50 == 0, d / 50 < count else { return nil }
        return d / 50
    }

    public static func clampedIndex(_ i: Int) -> Int { max(0, min(count - 1, i)) }

    public static var titles: [String] { (0..<count).map { "\(hz(index: $0)) Hz" } }
}

/// ComboBox2 / Settings › CW Bandwidth: SetBw, Ini.Bandwidth := 100 + No·50.
public enum BandwidthTable {
    public static let count = 11
    /// Ini.pas default ReadInteger(..., 'BandWidth', 9) = 550 Hz.
    public static let defaultIndex = 9
    /// Run(rmHst): ComboBox2.ItemIndex := 10; SetBw(10) — 600 Hz.
    public static let hstIndex = 10

    public static func hz(index: Int) -> Int { 100 + index * 50 }

    /// SetBw ignores indexes outside the list.
    public static func isValid(index: Int) -> Bool { index >= 0 && index < count }

    public static func index(hz: Int) -> Int? {
        let d = hz - 100
        guard d >= 0, d % 50 == 0, d / 50 < count else { return nil }
        return d / 50
    }

    /// A stored value as a combo index: unknown values fall back to the
    /// default so the combo, the RIT marker and the engine agree.
    public static func index(storedHz hz: Int) -> Int { index(hz: hz) ?? defaultIndex }

    public static var titles: [String] { (0..<count).map { "\(hz(index: $0)) Hz" } }
}

/// IncSpeed / DecSpeed / NWPMClick.
public enum SpeedStep {
    public static let minWpm = 10
    public static let maxWpm = 120

    public static func clamp(_ wpm: Int) -> Int { max(minWpm, min(maxWpm, wpm)) }

    /// IncSpeed: Trunc(Wpm/5)·5 + 5, clamped.
    public static func up(_ wpm: Int) -> Int {
        clamp(Int((Double(wpm) / 5).rounded(.towardZero)) * 5 + 5)
    }

    /// DecSpeed: Ceil(Wpm/5)·5 − 5, clamped.
    public static func down(_ wpm: Int) -> Int {
        clamp(Int((Double(wpm) / 5).rounded(.up)) * 5 - 5)
    }
}

/// TSpinEdit (Spin.pas) with Main.dfm's ranges.
public struct SpinRange: Sendable, Equatable {
    public let min: Int
    public let max: Int
    public let maxLength: Int

    public init(min: Int, max: Int, maxLength: Int) {
        self.min = min
        self.max = max
        self.maxLength = maxLength
    }

    /// SpinEdit1: 10…120, MaxLength 3.
    public static let wpm = SpinRange(min: 10, max: 120, maxLength: 3)
    /// SpinEdit3: 1…9, MaxLength 1.
    public static let activity = SpinRange(min: 1, max: 9, maxLength: 1)
    /// SpinEdit2: 1…240. Main.dfm says MaxLength 2, which cannot hold
    /// 120 (a Duration menu value) or 240; 3 here (parity-checklist ◑).
    public static let duration = SpinRange(min: 1, max: 240, maxLength: 3)

    /// CheckValue.
    public func clamp(_ v: Int) -> Int { Swift.max(min, Swift.min(max, v)) }

    /// A value typed so far, applied while typing only when in range.
    /// (TSpinEdit hands out-of-range text to OnChange unclamped; the
    /// port waits for a usable value instead — parity-checklist ◑.)
    public func typedValue(_ text: String) -> Int? {
        guard let v = Int(text.trimmingCharacters(in: .whitespaces)), v >= min, v <= max else {
            return nil
        }
        return v
    }

    /// CMExit: the text clamped into range; unparsable text keeps the
    /// current value.
    public func committedValue(_ text: String, current: Int) -> Int {
        guard let v = Int(text.trimmingCharacters(in: .whitespaces)) else { return current }
        return clamp(v)
    }
}

/// IncRit / UpdateRitIndicator / Panel8MouseDown / Shape2MouseDown.
public enum Rit {
    public static let stepHz = 50
    public static let limitHz = 500

    /// IncRit(dF): −1 / +1 = ∓50 Hz, 0 = reset; clamped ±500.
    public static func step(_ ritHz: Int, by dF: Int) -> Int {
        let v: Int
        switch dF {
        case 0: v = 0
        case ..<0: v = ritHz - stepHz
        default: v = ritHz + stepHz
        }
        return max(-limitHz, min(limitHz, v))
    }

    /// Dragging the marker (not in v1.68, which only steps on a click):
    /// the marker moves 1 px per 9 Hz, as UpdateRitIndicator draws it, so a
    /// drag of `dx` px from `startHz` lands on startHz + 9·dx, snapped to the
    /// 50 Hz grid IncRit uses and clamped ±500.
    public static func dragged(from startHz: Int, dx: Double) -> Int {
        let raw = Double(startHz) + 9 * dx
        let snapped = Int((raw / Double(stepHz)).rounded(.toNearestOrAwayFromZero)) * stepHz
        return max(-limitHz, min(limitHz, snapped))
    }

    /// Shape2: Width := Bandwidth div 9; Left := ((Panel8.Width − Width)
    /// div 2) + Rit div 9; Top 1, Height 7 in the 9-px Panel8.
    public static func marker(panelWidth: Int, panelHeight: Int, bandwidthHz: Int, ritHz: Int)
        -> (x: Int, y: Int, width: Int, height: Int) {
        let w = bandwidthHz / 9
        return (((panelWidth - w) / 2) + ritHz / 9, 1, w, panelHeight - 2)
    }

    /// What a press at (x, y) in Panel8 does: IncRit's argument, or nil.
    /// On Shape2 → 0. Elsewhere Panel8MouseDown: X < Left → −1,
    /// X > Left + Width → +1; the column above/below the marker and its
    /// right edge do nothing.
    public static func hit(x: Int, y: Int, panelWidth: Int, panelHeight: Int,
                           bandwidthHz: Int, ritHz: Int) -> Int? {
        let m = marker(panelWidth: panelWidth, panelHeight: panelHeight,
                       bandwidthHz: bandwidthHz, ritHz: ritHz)
        if x >= m.x, x < m.x + m.width, y >= m.y, y < m.y + m.height { return 0 }
        if x < m.x { return -1 }
        if x > m.x + m.width { return 1 }
        return nil
    }
}
