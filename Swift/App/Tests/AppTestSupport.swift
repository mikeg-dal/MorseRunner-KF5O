// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// A fake engine and a controller wired to a scratch defaults suite and a
// temporary directory: nothing touches the user's preferences or files.

import AppKit
import Foundation
import MRAppCore
@testable import MorseRunner
import MRPersistence
import MRSimulation

@MainActor
final class FakeEngine: EngineCommanding {
    enum Call: Equatable {
        case start, shutdown, configure(ContestSettings), runMode(RunMode), requestStop
        case send(Message, String), logQso(String), editCall(String), abortSend
        case recording(URL?)
        case myCall(String), wpm(Int), pitch(Int), bandwidth(Int), rit(Int), qsk(Bool)
        case activity(Int), duration(Int), monitorLevel(Float), callsFromKeyer(Bool)
        case conditions(Bool, Bool, Bool, Bool, Bool)
    }

    weak var events: (any EngineEvents)?
    var calls: [Call] = []
    /// The block time logQso reports.
    var blockSeconds: Double = 125

    var sent: [Message] {
        calls.compactMap { if case .send(let m, _) = $0 { m } else { nil } }
    }

    func start() { calls.append(.start) }
    func shutdown() { calls.append(.shutdown) }
    func configure(_ s: ContestSettings) { calls.append(.configure(s)) }
    func setRunMode(_ m: RunMode) { calls.append(.runMode(m)) }
    func requestStop() { calls.append(.requestStop) }
    func send(_ m: Message, callField: String) { calls.append(.send(m, callField)) }
    func logQso(_ call: String, stamped: @escaping @MainActor @Sendable (Double) -> Void) {
        calls.append(.logQso(call))
        stamped(blockSeconds)
    }
    func editCall(_ text: String) { calls.append(.editCall(text)) }
    func abortSend() { calls.append(.abortSend) }
    func setRecording(_ url: URL?) { calls.append(.recording(url)) }
    func setMyCall(_ v: String) { calls.append(.myCall(v)) }
    func setWpm(_ v: Int) { calls.append(.wpm(v)) }
    func setPitch(_ v: Int) { calls.append(.pitch(v)) }
    func setBandwidth(_ v: Int) { calls.append(.bandwidth(v)) }
    func setRit(_ v: Int) { calls.append(.rit(v)) }
    func setQsk(_ v: Bool) { calls.append(.qsk(v)) }
    func setActivity(_ v: Int) { calls.append(.activity(v)) }
    func setDuration(_ v: Int) { calls.append(.duration(v)) }
    func setMonitorLevel(_ v: Float) { calls.append(.monitorLevel(v)) }
    func setCallsFromKeyer(_ v: Bool) { calls.append(.callsFromKeyer(v)) }
    func setConditions(qrn: Bool, qrm: Bool, qsb: Bool, flutter: Bool, lids: Bool) {
        calls.append(.conditions(qrn, qrm, qsb, flutter, lids))
    }
}

/// A controller with a fake engine, a throwaway defaults suite and a
/// temporary base directory. Side-effect hooks record instead of acting.
@MainActor
final class Harness {
    let engine = FakeEngine()
    let suiteName = "com.garciamike1.morserunner.apptests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: Settings
    let dir: URL
    let controller: MainWindowController
    var beeps = 0
    var messages: [String] = []
    var scoreDialogs: [(String, Bool)] = []
    var opened: [URL] = []

    init(stored: [String: Any] = [:]) {
        defaults = UserDefaults(suiteName: suiteName)!
        for (k, v) in stored { defaults.set(v, forKey: k) }
        settings = Settings(defaults: defaults)
        dir = FileManager.default.temporaryDirectory.appending(path: "mr-apptests-\(UUID().uuidString)")
        controller = MainWindowController(engine: engine, settings: settings, files: ScoreFiles(baseDir: dir))
        controller.beep = { [unowned self] in beeps += 1 }
        controller.showMessage = { [unowned self] in messages.append($0) }
        controller.showScoreDialog = { [unowned self] in scoreDialogs.append(($0, $1)) }
        controller.openURL = { [unowned self] in opened.append($0) }
        controller.now = { Date(timeIntervalSince1970: 1_772_600_767) }  // 2026-03-04 05:06:07 UTC
        controller.timeZone = { TimeZone(identifier: "UTC")! }
        controller.loadSettings()
    }

    /// Keys the scratch suite holds (not the registration domain).
    var storedKeys: Set<String> {
        Set(defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? [])
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
        controller.window.delegate = nil
        controller.teardown()
    }

    func key(_ chars: String, ignoring: String? = nil, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: controller.window.windowNumber, context: nil,
                         characters: chars, charactersIgnoringModifiers: ignoring ?? chars,
                         isARepeat: false, keyCode: 0)!
    }

    func functionKey(_ code: UInt32, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let s = String(Character(Unicode.Scalar(code)!))
        return key(s, ignoring: s, flags)
    }

    func mouse(_ type: NSEvent.EventType, in view: NSView, at p: NSPoint, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: [],
                           timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
}
