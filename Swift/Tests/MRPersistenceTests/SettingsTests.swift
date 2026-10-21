// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MRPersistence.Settings against src/persistence/Settings.cpp. Every test
// uses its own throwaway UserDefaults suite, never the real
// com.garciamike1.MorseRunner domain.

import Foundation
@testable import MRPersistence
import Testing

/// A fresh, empty defaults suite, removed when the Scratch is released.
/// Keep the Scratch itself alive for the whole test (not just its
/// `defaults`), or the suite is wiped mid-test.
///
/// The suite name is an absolute path in a private temporary directory
/// (CFPreferences accepts a path as a domain), so the backing plist lives
/// there rather than in ~/Library/Preferences, where cfprefsd would leave
/// an empty <suite>.plist behind for every test. Nothing here can reach
/// the real com.garciamike1.MorseRunner domain.
private final class Scratch {
    let directory: URL
    let name: String
    let defaults: UserDefaults

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        name = directory.appendingPathComponent("settings").path
        defaults = UserDefaults(suiteName: name)!
        precondition(defaults.dictionaryRepresentation()[Settings.Key.call] == nil)
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A plist value as QSettings or a hand edit may leave it.
enum PlistValue: Sendable, CustomTestStringConvertible {
    case string(String), int(Int), double(Double), bool(Bool)

    var object: Any {
        switch self {
        case let .string(v): v
        case let .int(v): v
        case let .double(v): v
        case let .bool(v): v
        }
    }

    var testDescription: String {
        switch self {
        case let .string(v): "\"\(v)\""
        case let .int(v): "\(v)"
        case let .double(v): "\(v)"
        case let .bool(v): "\(v)"
        }
    }
}

@Test func freshInstallUsesPascalFirstRunDefaults() {
    let scratch = Scratch()
    let s = Settings(defaults: scratch.defaults).load()
    #expect(s == UserSettings())
    #expect(s.myCallsign == "VE3NEA")
    #expect(s.wpm == 30)
    #expect(s.pitchHz == 450)
    #expect(s.bandwidthHz == 550)
    #expect(s.activity == 2)
    #expect(s.durationMinutes == 30)
    #expect(s.monitorLevel == 0.75)
    #expect(s.qsk && s.qrn && s.qrm && s.qsb && s.flutter && s.lids)
    #expect(s.hiScore == 0)
    #expect(s.hamName == "")
    #expect(!s.saveWav)
    #expect(s.competitionDuration == 60)
    #expect(!s.callsFromKeyer)
}

@Test func settersRoundTrip() {
    let scratch = Scratch()
    let st = Settings(defaults: scratch.defaults)
    st.setMyCallsign("KF5O")
    st.setWpm(25)
    st.setPitchHz(600)
    st.setBandwidthHz(300)
    st.setActivity(5)
    st.setDurationMinutes(10)
    st.setMonitorLevel(0.26)
    st.setQsk(false)
    st.setQrn(false)
    st.setQrm(false)
    st.setQsb(false)
    st.setFlutter(false)
    st.setLids(false)
    st.setHiScore(1234)
    st.setHamName("Mike")
    st.setSaveWav(true)

    var want = UserSettings()
    want.myCallsign = "KF5O"
    want.wpm = 25
    want.pitchHz = 600
    want.bandwidthHz = 300
    want.activity = 5
    want.durationMinutes = 10
    want.monitorLevel = 0.26
    want.qsk = false
    want.qrn = false
    want.qrm = false
    want.qsb = false
    want.flutter = false
    want.lids = false
    want.hiScore = 1234
    want.hamName = "Mike"
    want.saveWav = true
    #expect(st.load() == want)
    #expect(st.hiScore() == 1234)
    #expect(st.hamName() == "Mike")
    #expect(st.saveWav())
    // A second instance over the same store sees the writes.
    #expect(Settings(defaults: scratch.defaults).load() == want)
}

@Test func standaloneGettersDefaultWhenMissing() {
    let scratch = Scratch()
    let st = Settings(defaults: scratch.defaults)
    #expect(st.hiScore() == 0)
    #expect(st.hamName() == "")
    #expect(!st.saveWav())
}

/// One row per persisted key: storing `value` (native plist type) under
/// `key` changes exactly the field `apply` sets, nothing else.
struct KeyCase: Sendable, CustomTestStringConvertible {
    let key: String
    let value: PlistValue
    let apply: @Sendable (inout UserSettings) -> Void
    var testDescription: String { "\(key) = \(value.testDescription)" }
}

private let everyKey: [KeyCase] = [
    KeyCase(key: "Station.Call", value: .string("KF5O")) { $0.myCallsign = "KF5O" },
    KeyCase(key: "Station.Wpm", value: .int(25)) { $0.wpm = 25 },
    KeyCase(key: "Station.Pitch", value: .int(600)) { $0.pitchHz = 600 },
    KeyCase(key: "Station.BandWidth", value: .int(300)) { $0.bandwidthHz = 300 },
    KeyCase(key: "Station.Qsk", value: .bool(false)) { $0.qsk = false },
    KeyCase(key: "Station.SelfMonVolume", value: .double(0.26)) { $0.monitorLevel = 0.26 },
    KeyCase(key: "Band.Activity", value: .int(5)) { $0.activity = 5 },
    KeyCase(key: "Band.Qrn", value: .bool(false)) { $0.qrn = false },
    KeyCase(key: "Band.Qrm", value: .bool(false)) { $0.qrm = false },
    KeyCase(key: "Band.Qsb", value: .bool(false)) { $0.qsb = false },
    KeyCase(key: "Band.Flutter", value: .bool(false)) { $0.flutter = false },
    KeyCase(key: "Band.Lids", value: .bool(false)) { $0.lids = false },
    KeyCase(key: "Contest.Duration", value: .int(10)) { $0.durationMinutes = 10 },
    KeyCase(key: "Contest.HiScore", value: .int(1234)) { $0.hiScore = 1234 },
    KeyCase(key: "Station.Name", value: .string("Mike")) { $0.hamName = "Mike" },
    KeyCase(key: "Station.SaveWav", value: .bool(true)) { $0.saveWav = true },
    KeyCase(key: "Contest.CompetitionDuration", value: .int(30)) { $0.competitionDuration = 30 },
    KeyCase(key: "Station.CallsFromKeyer", value: .bool(true)) { $0.callsFromKeyer = true },
]

@Test func everyKeyIsCovered() {
    #expect(everyKey.count == 18)
    #expect(Set(everyKey.map(\.key)).count == 18)
}

@Test(arguments: everyKey)
func eachKeyLoadsIntoItsField(_ c: KeyCase) {
    let scratch = Scratch()
    scratch.defaults.set(c.value.object, forKey: c.key)
    var want = UserSettings()
    c.apply(&want)
    #expect(want != UserSettings())                   // the row tests a change
    #expect(Settings(defaults: scratch.defaults).load() == want)
}

@Test func keysAndPlistTypesMatchQSettings() {
    // QSettings on macOS stores "Station/Call" as "Station.Call" with
    // native plist types; the Swift writer must produce the same.
    let scratch = Scratch()
    let st = Settings(defaults: scratch.defaults)
    st.setMyCallsign("KF5O")
    st.setWpm(20)
    st.setMonitorLevel(0.26)
    st.setQsk(false)
    st.setHiScore(1)
    let d = scratch.defaults
    #expect(d.object(forKey: "Station.Call") as? String == "KF5O")
    #expect((d.object(forKey: "Station.Wpm") as? NSNumber).map { CFNumberIsFloatType($0) } == false)
    #expect(d.integer(forKey: "Station.Wpm") == 20)
    #expect((d.object(forKey: "Station.SelfMonVolume") as? NSNumber).map { CFNumberIsFloatType($0) } == true)
    let qsk = d.object(forKey: "Station.Qsk") as? NSNumber
    #expect(qsk.map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true)
    #expect(d.integer(forKey: "Contest.HiScore") == 1)
    #expect(Settings.Key.bandwidth == "Station.BandWidth")
    #expect(Settings.Key.competitionDuration == "Contest.CompetitionDuration")
    #expect(Settings.domain == "com.garciamike1.MorseRunner")
}

@Test func readsAnExistingQtWrittenDomain() {
    // Exactly what the C++ build leaves in the plist (plutil -p of a real
    // com.garciamike1.MorseRunner.plist): booleans as <true/>/<false/>,
    // SelfMonVolume as <real>, Rit as <integer>.
    let scratch = Scratch()
    let d = scratch.defaults
    d.set(1, forKey: "Band.Activity")
    d.set(false, forKey: "Band.Flutter")
    d.set(false, forKey: "Band.Lids")
    d.set(false, forKey: "Band.Qrm")
    d.set(false, forKey: "Band.Qrn")
    d.set(false, forKey: "Band.Qsb")
    d.set(3, forKey: "Contest.Duration")
    d.set(1, forKey: "Contest.HiScore")
    d.set(600, forKey: "Station.BandWidth")
    d.set("KF5O", forKey: "Station.Call")
    d.set(450, forKey: "Station.Pitch")
    d.set(false, forKey: "Station.Qsk")
    d.set(-100, forKey: "Station.Rit")          // RIT is not persisted; ignored
    d.set(false, forKey: "Station.SaveWav")
    d.set(0.26, forKey: "Station.SelfMonVolume")
    d.set(20, forKey: "Station.Wpm")
    let s = Settings(defaults: d).load()
    #expect(s.activity == 1)
    #expect(!s.flutter && !s.lids && !s.qrm && !s.qrn && !s.qsb && !s.qsk && !s.saveWav)
    #expect(s.durationMinutes == 3)
    #expect(s.hiScore == 1)
    #expect(s.bandwidthHz == 600)
    #expect(s.myCallsign == "KF5O")
    #expect(s.pitchHz == 450)
    #expect(s.monitorLevel == 0.26)
    #expect(s.wpm == 20)
    #expect(s.competitionDuration == 60)
}

@Test func readsAQtDomainWithStringNumbersAndIntegerBools() {
    // QVariant can also serialize numbers as strings and bools as
    // integers (older Qt builds, hand edits); they convert the same way.
    let scratch = Scratch()
    let d = scratch.defaults
    d.set("0.26", forKey: "Station.SelfMonVolume")
    d.set("-100", forKey: "Station.Rit")
    d.set("20", forKey: "Station.Wpm")
    d.set(0, forKey: "Band.Qrn")
    d.set(1, forKey: "Station.SaveWav")
    d.set(0, forKey: "Station.Qsk")
    let s = Settings(defaults: d).load()
    #expect(s.monitorLevel == 0.26)
    #expect(s.wpm == 20)
    #expect(!s.qrn && s.saveWav && !s.qsk)
}

@Test(arguments: [(5, 10), (10, 10), (55, 55), (120, 120), (500, 120), (-3, 10)])
func wpmIsClamped(stored: Int, loaded: Int) {
    let scratch = Scratch()
    Settings(defaults: scratch.defaults).setWpm(stored)
    #expect(Settings(defaults: scratch.defaults).load().wpm == loaded)
}

@Test(arguments: [(0, 1), (1, 1), (30, 30), (60, 60), (61, 60), (-5, 1)])
func competitionDurationIsClamped(stored: Int, loaded: Int) {
    let scratch = Scratch()
    scratch.defaults.set(stored, forKey: Settings.Key.competitionDuration)
    #expect(Settings(defaults: scratch.defaults).load().competitionDuration == loaded)
}

@Test(arguments: [(300, 300), (450, 450), (900, 900), (474, 450), (475, 500), (899, 900),
                  (299, 450), (901, 450), (0, 450), (-600, 450)])
func pitchSnapsToComboValues(stored: Int, loaded: Int) {
    let scratch = Scratch()
    Settings(defaults: scratch.defaults).setPitchHz(stored)
    #expect(Settings(defaults: scratch.defaults).load().pitchHz == loaded)
}

@Test(arguments: [(100, 100), (600, 600), (124, 100), (125, 150), (575, 600),
                  (99, 550), (601, 550), (0, 550)])
func bandwidthSnapsToComboValues(stored: Int, loaded: Int) {
    let scratch = Scratch()
    Settings(defaults: scratch.defaults).setBandwidthHz(stored)
    #expect(Settings(defaults: scratch.defaults).load().bandwidthHz == loaded)
}

@Test(arguments: [(0, 1), (1, 1), (5, 5), (9, 9), (10, 9), (-3, 1)])
func activityIsClamped(stored: Int, loaded: Int) {
    let scratch = Scratch()
    Settings(defaults: scratch.defaults).setActivity(stored)
    #expect(Settings(defaults: scratch.defaults).load().activity == loaded)
}

@Test(arguments: [(0, 1), (-5, 1), (1, 1), (240, 240), (999, 999)])
func durationIsAtLeastOneMinute(stored: Int, loaded: Int) {
    let scratch = Scratch()
    Settings(defaults: scratch.defaults).setDurationMinutes(stored)
    #expect(Settings(defaults: scratch.defaults).load().durationMinutes == loaded)
}

@Test(arguments: [(PlistValue.double(-0.5), 0.0), (.double(1.5), 1.0), (.double(0.26), 0.26),
                  (.double(0), 0), (.double(1), 1), (.double(.infinity), 0.75),
                  (.double(-.infinity), 0.75), (.string("nan"), 0), (.string("inf"), 0),
                  (.string("2"), 1), (.bool(true), 1)])
func monitorLevelIsClampedToUnitRange(stored: PlistValue, loaded: Double) {
    let scratch = Scratch()
    scratch.defaults.set(stored.object, forKey: Settings.Key.monitor)
    #expect(Settings(defaults: scratch.defaults).load().monitorLevel == loaded)
}

@Test func callsFromKeyerIsRead() {
    let scratch = Scratch()
    scratch.defaults.set(true, forKey: Settings.Key.callsFromKeyer)
    #expect(Settings(defaults: scratch.defaults).load().callsFromKeyer)
}

@Test func qvariantStyleConversions() {
    // Values hand-edited into the plist as strings convert like QVariant.
    let scratch = Scratch()
    let d = scratch.defaults
    d.set("25", forKey: Settings.Key.wpm)
    d.set("0.5", forKey: Settings.Key.monitor)
    d.set("false", forKey: Settings.Key.qrn)
    d.set("1", forKey: Settings.Key.qrm)
    d.set("abc", forKey: Settings.Key.hiScore)    // unconvertible → 0, not the default
    d.set("abc", forKey: Settings.Key.activity)   // → 0, then clamped to 1
    d.set(42, forKey: Settings.Key.call)
    let s = Settings(defaults: d).load()
    #expect(s.wpm == 25)
    #expect(s.monitorLevel == 0.5)
    #expect(!s.qrn)
    #expect(s.qrm)
    #expect(s.hiScore == 0)
    #expect(s.activity == 1)
    #expect(s.myCallsign == "42")
}

@Test func hugeAndNonFiniteNumbersDoNotTrap() {
    let scratch = Scratch()
    let d = scratch.defaults
    d.set(1e30, forKey: Settings.Key.wpm)
    d.set(1e30, forKey: Settings.Key.hiScore)
    d.set(-1e30, forKey: Settings.Key.duration)
    d.set("nan", forKey: Settings.Key.competitionDuration)
    d.set(Double.infinity, forKey: Settings.Key.activity)
    let s = Settings(defaults: d).load()
    #expect(s.wpm == 120)
    #expect(s.hiScore == Int(Int32.max))
    #expect(s.durationMinutes == 1)
    #expect(s.competitionDuration == 1)                // "nan" → 0 → clamp
    #expect(s.activity == 1)                           // inf → 0 → clamp
}

@Test(arguments: [(20.5, 21), (20.4, 20), (20.49999, 20), (-2.5, -3), (-0.4, 0),
                  (1e30, Int(Int32.max)), (-1e30, Int(Int32.min)),
                  (Double.nan, 0), (Double.infinity, 0), (-Double.infinity, 0)])
func toIntRoundsLikeQRoundAndSaturates(value: Double, int: Int) {
    #expect(Settings.toInt(NSNumber(value: value)) == int)
}

@Test func toIntOfOtherTypes() {
    #expect(Settings.toInt(NSNumber(value: true)) == 1)
    #expect(Settings.toInt(NSNumber(value: false)) == 0)
    #expect(Settings.toInt(NSNumber(value: 42)) == 42)
    #expect(Settings.toInt(" 17 ") == 17)
    #expect(Settings.toInt("17.5") == 0)               // QString::toInt rejects decimals
    #expect(Settings.toInt("1e30") == 0)
    #expect(Settings.toInt(Date()) == 0)
}

@Test func toDoubleRejectsNonFiniteStrings() {
    for s in ["nan", "NaN", "inf", "-inf", "infinity", "abc", ""] {
        #expect(Settings.toDouble(s) == 0, "\(s)")
    }
    #expect(Settings.toDouble(" 0.25 ") == 0.25)
    #expect(Settings.toDouble(NSNumber(value: true)) == 1)
    #expect(Settings.toDouble(NSNumber(value: 3)) == 3)
    #expect(Settings.toDouble(Date()) == 0)
}

@Test func toBoolConversions() {
    #expect(Settings.toBool(NSNumber(value: 0)) == false)
    #expect(Settings.toBool(NSNumber(value: 1)) == true)
    #expect(Settings.toBool(NSNumber(value: 2)) == true)
    #expect(Settings.toBool(NSNumber(value: 0.0)) == false)
    for s in ["", "0", "false", "FALSE", "False"] { #expect(!Settings.toBool(s), "\(s)") }
    for s in ["1", "true", "yes", "x"] { #expect(Settings.toBool(s), "\(s)") }
    #expect(!Settings.toBool(Date()))
}

@Test func toStringConversions() {
    #expect(Settings.toString("KF5O") == "KF5O")
    #expect(Settings.toString(NSNumber(value: 42)) == "42")
    #expect(Settings.toString(NSNumber(value: 0.5)) == "0.5")
    #expect(Settings.toString(NSNumber(value: true)) == "true")
    #expect(Settings.toString(NSNumber(value: false)) == "false")
    #expect(Settings.toString(Date()) == "")
}

@Test func boolStoredAsNumberLoads() {
    let scratch = Scratch()
    let d = scratch.defaults
    d.set(0, forKey: Settings.Key.lids)
    d.set(2, forKey: Settings.Key.saveWav)
    d.set(0.0, forKey: Settings.Key.flutter)
    let s = Settings(defaults: d).load()
    #expect(!s.lids && s.saveWav && !s.flutter)
}

// MARK: - shared() never reaches the real domain under tests

@Test func thisProcessIsDetectedAsATestRunner() {
    #expect(Settings.isTestProcess())
}

@Test func sharedUsesTheTestSuiteOrTheOverride() {
    let override = ProcessInfo.processInfo.environment[Settings.suiteEnvironmentVariable]
    let st = Settings.shared()
    if let override, !override.isEmpty {
        #expect(st.suiteName == override)
    } else {
        #expect(st.suiteName == Settings.testSuite)
    }
    #expect(st.suiteName?.caseInsensitiveCompare(Settings.domain) != .orderedSame)
    #expect(st.suiteName != nil)                       // never .standard either
}

struct SuiteCase: Sendable, CustomTestStringConvertible {
    let env: [String: String]
    let bundleID: String?
    let isTest: Bool
    let expected: String?
    var testDescription: String { "env=\(env) bundle=\(bundleID ?? "nil") test=\(isTest)" }
}

@Test(arguments: [
    SuiteCase(env: ["MR_DEFAULTS_SUITE": "x.y"], bundleID: "com.garciamike1.MorseRunner",
              isTest: false, expected: "x.y"),
    SuiteCase(env: ["MR_DEFAULTS_SUITE": "x.y"], bundleID: nil, isTest: true, expected: "x.y"),
    SuiteCase(env: ["MR_DEFAULTS_SUITE": ""], bundleID: nil, isTest: true,
              expected: "com.garciamike1.MorseRunner.tests"),
    SuiteCase(env: [:], bundleID: "com.garciamike1.morserunner", isTest: true,
              expected: "com.garciamike1.MorseRunner.tests"),
    SuiteCase(env: [:], bundleID: "com.garciamike1.morserunner", isTest: false, expected: nil),
    SuiteCase(env: [:], bundleID: "com.garciamike1.MorseRunner", isTest: false, expected: nil),
    SuiteCase(env: [:], bundleID: "com.example.other", isTest: false,
              expected: "com.garciamike1.MorseRunner"),
    SuiteCase(env: [:], bundleID: nil, isTest: false, expected: "com.garciamike1.MorseRunner"),
])
func sharedSuiteResolution(_ c: SuiteCase) {
    #expect(Settings.resolveSuite(environment: c.env, bundleIdentifier: c.bundleID,
                                  isTestProcess: c.isTest) == c.expected)
}

@Test func clampAndComboHelpers() {
    #expect(Settings.clamp(5, 1...9) == 5)
    #expect(Settings.clamp(0, 1...9) == 1)
    #expect(Settings.clamp(10, 1...9) == 9)
    #expect(Settings.comboValue(325, range: 300...900, step: 50, default: 450) == 350)
    #expect(Settings.comboValue(324, range: 300...900, step: 50, default: 450) == 300)
    #expect(Settings.comboValue(Int.max, range: 300...900, step: 50, default: 450) == 450)
}
