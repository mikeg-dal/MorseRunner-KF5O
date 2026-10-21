// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// UserDefaults-backed persistence; port of src/persistence/Settings.
// The C++ port uses QSettings(NativeFormat, UserScope, "garciamike1",
// "MorseRunner"), which on macOS writes the defaults domain
// com.garciamike1.MorseRunner and turns the group separator '/' into
// '.', so "Station/Call" is stored as "Station.Call". This port reads
// and writes the same domain and key strings with the same plist types
// (string / integer / real / boolean), so existing users' settings
// carry over in both directions. Schema mirrors the Pascal Ini groups
// (Station / Band / Contest).
//
// RIT is deliberately not persisted (Pascal does not save it either).
//
// Range checks on load (the plist can be hand-edited or written by an
// older build): the values are forced into what the controls they feed
// can hold, as the Pascal controls do when FromIni assigns them —
//  - Wpm 10...120 (Pascal: Wpm := Max(10, Min(120, Wpm))).
//  - CompetitionDuration 1...60 (Pascal FromIni clamp).
//  - SelfMonVolume clamped to 0...1; not finite → default (Pascal
//    TVolumeSlider.SetValue clamps to 0..1).
//  - Pitch / BandWidth: combo values only (300...900 / 100...600 Hz in
//    50 Hz steps, C++ RightPanel combos). An in-range value is snapped
//    to the nearest step; an out-of-range one falls back to the default
//    (the combo would have no matching item).
//  - Activity 1...9 and Duration >= 1 (Pascal SpinEdit MinValue /
//    MaxValue; C++ kActivityMin/Max, kDurationMin). Duration has no
//    upper clamp here; the duration field enforces its own limit.

import Foundation

/// Snapshot of every persisted control. Default values match the
/// Pascal Ini.pas defaults so a fresh install behaves identically to a
/// fresh original install.
public struct UserSettings: Equatable, Sendable {
    // Pascal FromIni defaults when a key is missing (a fresh install
    // ships no .ini): Pitch combo index 3 = 450 Hz, BandWidth index 9 =
    // 550 Hz, Activity 2. These override the form's 600 / 500 / 3.
    public var myCallsign = "VE3NEA"
    public var wpm = 30
    public var pitchHz = 450
    public var bandwidthHz = 550
    public var activity = 2
    public var durationMinutes = 30
    public var monitorLevel = 0.75   // selfMonGain01

    public var qsk = true
    public var qrn = true
    public var qrm = true
    public var qsb = true
    public var flutter = true
    public var lids = true

    /// Pascal Ini.pas SEC_TST/HiScore. The WPX ScoreDialog uses it to
    /// decide whether to show the "Congratulations on a new record!"
    /// banner.
    public var hiScore = 0
    /// Pascal SEC_STN/Name. Set via Settings → HST Operator… and
    /// appended to the window title plus written to the HST result
    /// logfile.
    public var hamName = ""
    /// Pascal SEC_STN/SaveWav. File → Audio Recording Enabled toggle.
    public var saveWav = false
    // INI-only keys (no UI in the original either; edit the plist).
    /// SEC_TST/CompetitionDuration: WPX / HST run length, clamped 1..60.
    public var competitionDuration = 60
    /// SEC_STN/CallsFromKeyer: an external keyer sends the call.
    public var callsFromKeyer = false

    public init() {}
}

/// Sendable: the stored properties are immutable; the UserDefaults store
/// is documented thread-safe by Apple but not annotated Sendable in the
/// macOS 15 SDK, hence @unchecked.
public final class Settings: @unchecked Sendable {
    /// The QSettings domain of the C++ port (organization "garciamike1",
    /// application "MorseRunner").
    public static let domain = "com.garciamike1.MorseRunner"

    /// Environment variable naming a defaults suite to use instead of
    /// the real domain (e.g. for UI tests or a scratch profile).
    public static let suiteEnvironmentVariable = "MR_DEFAULTS_SUITE"

    /// The suite shared() uses when it detects a test process and no
    /// MR_DEFAULTS_SUITE override is set: tests never touch the user's
    /// real preferences.
    public static let testSuite = "com.garciamike1.MorseRunner.tests"

    /// Range limits applied on load (see the file header).
    public enum Limits {
        public static let wpm = 10...120
        public static let competitionDuration = 1...60
        public static let pitchHz = 300...900
        public static let pitchStepHz = 50
        public static let bandwidthHz = 100...600
        public static let bandwidthStepHz = 50
        public static let activity = 1...9
        public static let minDurationMinutes = 1
        public static let monitorLevel = 0.0...1.0
    }

    /// Key strings as QSettings stores them on macOS ('/' → '.').
    /// Layout matches Pascal Ini.pas sections.
    public enum Key {
        public static let call = "Station.Call"
        public static let wpm = "Station.Wpm"
        public static let pitch = "Station.Pitch"
        public static let bandwidth = "Station.BandWidth"
        public static let qsk = "Station.Qsk"
        public static let monitor = "Station.SelfMonVolume"

        public static let activity = "Band.Activity"
        public static let qrn = "Band.Qrn"
        public static let qrm = "Band.Qrm"
        public static let qsb = "Band.Qsb"
        public static let flutter = "Band.Flutter"
        public static let lids = "Band.Lids"

        public static let duration = "Contest.Duration"
        public static let hiScore = "Contest.HiScore"
        public static let hamName = "Station.Name"
        public static let saveWav = "Station.SaveWav"
        public static let competitionDuration = "Contest.CompetitionDuration"
        public static let callsFromKeyer = "Station.CallsFromKeyer"
    }

    private let store: UserDefaults
    /// The suite name this instance was opened with (nil = .standard).
    let suiteName: String?

    /// `defaults` is the backing store; tests pass a throwaway suite.
    public init(defaults: UserDefaults) {
        store = defaults
        suiteName = nil
    }

    private init(suite: String?) {
        store = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        suiteName = suite
    }

    /// Opens the store the C++ port uses. Each call returns a new
    /// (cheap) instance over the same process-wide defaults; keep one
    /// per owner rather than calling it repeatedly.
    ///
    /// Store selection, in order:
    ///  1. `MR_DEFAULTS_SUITE` set (non-empty) → that suite.
    ///  2. Running under XCTest / Swift Testing → `testSuite`, so no
    ///     test can read or write the user's real preferences.
    ///  3. The running app's bundle ID is the domain (case-insensitively,
    ///     as the preferences file system is) → `UserDefaults.standard`.
    ///  4. Otherwise the named suite `domain`.
    public static func shared() -> Settings {
        let info = ProcessInfo.processInfo
        return Settings(suite: resolveSuite(environment: info.environment,
                                     bundleIdentifier: Bundle.main.bundleIdentifier,
                                     isTestProcess: isTestProcess(info)))
    }

    /// The suite shared() opens; nil means `UserDefaults.standard`.
    static func resolveSuite(environment: [String: String], bundleIdentifier: String?,
                             isTestProcess: Bool) -> String? {
        if let s = environment[suiteEnvironmentVariable], !s.isEmpty { return s }
        if isTestProcess { return testSuite }
        if let id = bundleIdentifier, id.caseInsensitiveCompare(domain) == .orderedSame {
            return nil
        }
        return domain
    }

    /// Heuristics for "this process is a test runner": XCTest's
    /// environment (also set for app-hosted tests), the XCTest class
    /// being loaded, or SwiftPM's test runners.
    static func isTestProcess(_ info: ProcessInfo = .processInfo) -> Bool {
        let env = info.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil { return true }
        let name = info.processName
        if name == "xctest" || name == "swiftpm-testing-helper" { return true }
        return Bundle.main.bundlePath.hasSuffix(".xctest")
    }

    /// Loads the latest values into a `UserSettings`. Missing keys fall
    /// back to their hard-coded defaults.
    /// Loaded values are range-checked as described in the file header.
    public func load() -> UserSettings {
        var s = UserSettings()
        let def = UserSettings()
        s.myCallsign = string(Key.call, s.myCallsign)
        s.wpm = int(Key.wpm, s.wpm)
        s.pitchHz = Self.comboValue(int(Key.pitch, s.pitchHz), range: Limits.pitchHz,
                                    step: Limits.pitchStepHz, default: def.pitchHz)
        s.bandwidthHz = Self.comboValue(int(Key.bandwidth, s.bandwidthHz),
                                        range: Limits.bandwidthHz,
                                        step: Limits.bandwidthStepHz, default: def.bandwidthHz)
        s.activity = Self.clamp(int(Key.activity, s.activity), Limits.activity)
        s.durationMinutes = max(int(Key.duration, s.durationMinutes), Limits.minDurationMinutes)
        let level = double(Key.monitor, s.monitorLevel)
        s.monitorLevel = level.isFinite ? Self.clamp(level, Limits.monitorLevel) : def.monitorLevel
        s.qsk = bool(Key.qsk, s.qsk)
        s.qrn = bool(Key.qrn, s.qrn)
        s.qrm = bool(Key.qrm, s.qrm)
        s.qsb = bool(Key.qsb, s.qsb)
        s.flutter = bool(Key.flutter, s.flutter)
        s.lids = bool(Key.lids, s.lids)
        s.hiScore = int(Key.hiScore, s.hiScore)
        s.hamName = string(Key.hamName, s.hamName)
        s.saveWav = bool(Key.saveWav, s.saveWav)
        // Pascal: Wpm := Max(10, Min(120, Wpm)); CompDuration clamped 1..60.
        s.wpm = Self.clamp(s.wpm, Limits.wpm)
        s.competitionDuration = Self.clamp(int(Key.competitionDuration, s.competitionDuration),
                                           Limits.competitionDuration)
        s.callsFromKeyer = bool(Key.callsFromKeyer, s.callsFromKeyer)
        return s
    }

    static func clamp<T: Comparable>(_ v: T, _ r: ClosedRange<T>) -> T {
        min(max(v, r.lowerBound), r.upperBound)
    }

    /// A combo-box value: in range → nearest step (ties round up),
    /// out of range → `default`.
    static func comboValue(_ v: Int, range: ClosedRange<Int>, step: Int, default def: Int) -> Int {
        guard range.contains(v) else { return def }
        let k = (v - range.lowerBound + step / 2) / step
        return min(range.lowerBound + k * step, range.upperBound)
    }

    // Per-field writers. UserDefaults persists without an explicit
    // synchronize (the C++ calls QSettings::sync() after each write).
    //
    // There are deliberately no setters for competitionDuration and
    // callsFromKeyer: like the C++ Settings (and Pascal, which has no UI
    // for them), they are INI-only keys the user edits by hand; the app
    // only reads them.
    public func setMyCallsign(_ v: String) { store.set(v, forKey: Key.call) }
    public func setWpm(_ v: Int) { store.set(v, forKey: Key.wpm) }
    public func setPitchHz(_ v: Int) { store.set(v, forKey: Key.pitch) }
    public func setBandwidthHz(_ v: Int) { store.set(v, forKey: Key.bandwidth) }
    public func setActivity(_ v: Int) { store.set(v, forKey: Key.activity) }
    public func setDurationMinutes(_ v: Int) { store.set(v, forKey: Key.duration) }
    public func setMonitorLevel(_ v: Double) { store.set(v, forKey: Key.monitor) }

    public func setQsk(_ v: Bool) { store.set(v, forKey: Key.qsk) }
    public func setQrn(_ v: Bool) { store.set(v, forKey: Key.qrn) }
    public func setQrm(_ v: Bool) { store.set(v, forKey: Key.qrm) }
    public func setQsb(_ v: Bool) { store.set(v, forKey: Key.qsb) }
    public func setFlutter(_ v: Bool) { store.set(v, forKey: Key.flutter) }
    public func setLids(_ v: Bool) { store.set(v, forKey: Key.lids) }

    public func hiScore() -> Int { int(Key.hiScore, 0) }
    public func setHiScore(_ v: Int) { store.set(v, forKey: Key.hiScore) }

    public func hamName() -> String { string(Key.hamName, "") }
    public func setHamName(_ v: String) { store.set(v, forKey: Key.hamName) }

    public func saveWav() -> Bool { bool(Key.saveWav, false) }
    public func setSaveWav(_ v: Bool) { store.set(v, forKey: Key.saveWav) }

    // MARK: - QVariant-style reads
    //
    // QSettings::value(key, def).toInt() etc.: a missing key yields the
    // default; a present value is converted, and an unconvertible one
    // yields 0 / false / "" (QVariant's failure value), not the default.

    private func int(_ key: String, _ def: Int) -> Int {
        guard let v = store.object(forKey: key) else { return def }
        return Self.toInt(v)
    }

    private func double(_ key: String, _ def: Double) -> Double {
        guard let v = store.object(forKey: key) else { return def }
        return Self.toDouble(v)
    }

    private func bool(_ key: String, _ def: Bool) -> Bool {
        guard let v = store.object(forKey: key) else { return def }
        return Self.toBool(v)
    }

    private func string(_ key: String, _ def: String) -> String {
        guard let v = store.object(forKey: key) else { return def }
        return Self.toString(v)
    }

    private static func isBool(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func toInt(_ v: Any) -> Int {
        if let n = v as? NSNumber {
            if isBool(n) { return n.boolValue ? 1 : 0 }
            if CFNumberIsFloatType(n) {
                // QVariant double → int rounds (qRound).
                return roundedInt(n.doubleValue)
            }
            return n.intValue
        }
        if let s = v as? String {
            return Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    /// Rounds half away from zero (qRound), saturating to the 32-bit
    /// range of QVariant::toInt (so 1e30 → Int32.max, never a trap). Not
    /// finite → 0 (QVariant's failure value).
    static func roundedInt(_ d: Double) -> Int {
        guard d.isFinite else { return 0 }
        let r = min(max(d.rounded(.toNearestOrAwayFromZero), Double(Int32.min)), Double(Int32.max))
        return Int(exactly: r) ?? 0
    }

    static func toDouble(_ v: Any) -> Double {
        if let n = v as? NSNumber {
            return isBool(n) ? (n.boolValue ? 1 : 0) : n.doubleValue
        }
        if let s = v as? String {
            // Double("nan") / Double("inf") parse in Swift; QString::toDouble
            // rejects them, so they convert to 0 here too.
            guard let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite else {
                return 0
            }
            return d
        }
        return 0
    }

    static func toBool(_ v: Any) -> Bool {
        if let n = v as? NSNumber {
            return n.boolValue
        }
        if let s = v as? String {
            // QVariant string → bool: false for "", "0" and "false".
            let l = s.lowercased()
            return !(l.isEmpty || l == "0" || l == "false")
        }
        return false
    }

    static func toString(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if isBool(n) { return n.boolValue ? "true" : "false" }
            if CFNumberIsFloatType(n) { return "\(n.doubleValue)" }
            return "\(n.intValue)"
        }
        return ""
    }
}
