// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The main window: Main.dfm's controls and Main.pas's state. The logic
// lives in MRAppCore; the extensions in MainWindowController+*.swift
// apply it (Layout, Menus, Operating, Files). Everything the original did
// on its GUI thread happens here on the main thread; everything it did
// inside Tst goes through EngineCommanding to the simulation thread.

import AppKit
import MRAppCore
import MRPersistence
import MRScoring
import MRSimulation

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate {
    let window: NSWindow
    let engine: any EngineCommanding
    let settings: Settings
    let files: ScoreFiles

    // ── Side effects, replaceable in tests ─────────────────────────────
    var beep: () -> Void = { NSSound.beep() }
    /// ShowMessage.
    var showMessage: (String) -> Void = { Dialogs.message($0) }
    /// ScoreDialog.ShowModal.
    var showScoreDialog: (_ line: String, _ newRecord: Bool) -> Void = { _, _ in }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var now: () -> Date = { Date() }
    var timeZone: () -> TimeZone = { TimeZone.current }

    // ── Main.dfm controls ──────────────────────────────────────────────
    let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 700, height: 413))
    let splash = SplashView(frame: NSRect(x: 1, y: 1, width: 484, height: 280))
    let logView = LogView(frame: NSRect(x: 1, y: 1, width: 484, height: 280))

    // Station group (GroupBox1)
    let myCallEdit = NSTextField()                          // Edit4
    let qskCheck = NSButton(checkboxWithTitle: "QSK", target: nil, action: nil)
    let wpmSpin = SpinEdit(frame: NSRect(x: 88, y: 44, width: 65, height: 22),
                           range: .wpm, value: 30, label: "CW Speed")
    let pitchCombo = NSPopUpButton()                        // ComboBox1
    let bwCombo = NSPopUpButton()                           // ComboBox2
    let volume = VolumeSlider(frame: NSRect(x: 89, y: 132, width: 60, height: 20))
    // Band conditions (GroupBox3)
    let qrnCheck = NSButton(checkboxWithTitle: "QRN", target: nil, action: nil)
    let qrmCheck = NSButton(checkboxWithTitle: "QRM", target: nil, action: nil)
    let qsbCheck = NSButton(checkboxWithTitle: "QSB", target: nil, action: nil)
    let flutterCheck = NSButton(checkboxWithTitle: "Flutter", target: nil, action: nil)
    let lidsCheck = NSButton(checkboxWithTitle: "LID's", target: nil, action: nil)
    let activitySpin = SpinEdit(frame: NSRect(x: 144, y: 32, width: 37, height: 22),
                                range: .activity, value: 3, label: "Activity")
    // Panel10
    let durationSpin = SpinEdit(frame: NSRect(x: 122, y: 7, width: 45, height: 22),
                                range: .duration, value: 30, label: "Duration")
    let runButton = NSSegmentedControl()                    // ToolButton1 (tbsDropDown)
    let runPopup = NSMenu()                                 // PopupMenu1

    // Bottom panel (Panel1)
    let callEdit = EntryTextField()                         // Edit1
    let rstEdit = EntryTextField()                          // Edit2
    let nrEdit = EntryTextField()                           // Edit3
    var fKeys: [NSButton] = []
    let modePanel = BevelPanel()                            // Panel4
    let ratePanel = BevelPanel()                            // Panel7
    let clockPanel = BevelPanel()                           // Panel2
    let histogram = HistogramView(frame: NSRect(x: 1, y: 1, width: 223, height: 59))
    let rit = RitView(frame: NSRect(x: 292, y: 103, width: 225, height: 9))
    let scoreTable = ScoreTableView(frame: NSRect(x: 529, y: 44, width: 163, height: 68))

    /// QRN, QRM, QSB, Flutter, LIDS — the order of the Settings items.
    var conditionChecks: [NSButton] { [qrnCheck, qrmCheck, qsbCheck, flutterCheck, lidsCheck] }

    // ── Menus (MainMenu1 + PopupMenu1) ─────────────────────────────────
    private(set) var mainMenu = NSMenu()
    private(set) var windowsMenu = NSMenu(title: "Window")
    var fileMenu = NSMenu(title: "File")
    var settingsMenu = NSMenu(title: "Settings")
    var runItems: [NSMenuItem] = []                         // Pile-Up..HST, main menu
    var popupRunItems: [NSMenuItem] = []
    var stopItem = NSMenuItem()
    var popupStopItem = NSMenuItem()
    var sendItems: [NSMenuItem] = []
    var callItem = NSMenuItem()
    var durationItem = NSMenuItem()
    var activityItem = NSMenuItem()
    var bandwidthItem = NSMenuItem()
    var qskItem = NSMenuItem()
    var conditionItems: [NSMenuItem] = []                   // QRN, QRM, QSB, Flutter, LIDS
    var audioRecordingItem = NSMenuItem()
    var playRecordingItem = NSMenuItem()

    // ── Main.pas / Log.pas / Ini.pas state ─────────────────────────────
    var op = OperatingState()                               // CallSent, NrSent, MustAdvance
    var runMode: RunMode = .stop                            // Ini.RunMode
    var log = QsoLog()
    var elapsed: Double = 0
    var ritHz = 0                                           // Ini.Rit
    var saveWav = false
    var competitionDuration = 60
    var hiScore = 0
    var hamName = ""
    var callsFromKeyer = false
    /// Bumped by every Run: answers for an earlier session are dropped.
    var runGeneration = 0
    private var keyMonitor: Any?

    init(engine: any EngineCommanding, settings: Settings, files: ScoreFiles) {
        self.engine = engine
        self.settings = settings
        self.files = files
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 413),
                          styleMask: [.titled, .closable, .miniaturizable],  // bsSingle + biSystemMenu
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init()
        window.title = Captions.windowTitle(hamName: "")
        window.contentView = root
        window.delegate = self
        window.appearance = NSAppearance(named: .aqua)  // the original is a light UI
        buildLayout()
        mainMenu = buildMainMenu()
        applyRunControls(RunModeRules.controls(for: .stop, competitionDuration: competitionDuration))
        engine.events = self
        showScoreDialog = { [weak self] line, newRecord in
            let dlg = ScoreDialog(scoreString: line, newRecord: newRecord)
            dlg.onHiScorePage = { self?.viewHiScorePage() }
            dlg.runModal(centeredOn: self?.window)
        }
    }

    // MARK: - Startup (FormCreate + FromIni)

    /// Ini.pas FromIni: shows the stored settings and hands them to the
    /// engine once. Nothing is written back.
    func loadSettings() {
        let s = settings.load()
        myCallEdit.stringValue = s.myCallsign.trimmingCharacters(in: .whitespaces)
        pitchCombo.selectItem(at: PitchTable.index(hz: s.pitchHz) ?? PitchTable.defaultIndex)
        let bw = BandwidthTable.index(storedHz: s.bandwidthHz)
        bwCombo.selectItem(at: bw)
        rit.bandwidthHz = BandwidthTable.hz(index: bw)
        hamName = s.hamName
        applyCaption()
        wpmSpin.setValueSilently(SpeedStep.clamp(s.wpm))
        qskCheck.state = s.qsk ? .on : .off
        callsFromKeyer = s.callsFromKeyer
        activitySpin.setValueSilently(s.activity)
        for (cb, on) in zip(conditionChecks, [s.qrn, s.qrm, s.qsb, s.flutter, s.lids]) {
            cb.state = on ? .on : .off
        }
        durationSpin.setValueSilently(s.durationMinutes)
        hiScore = s.hiScore
        competitionDuration = s.competitionDuration
        volume.setValueDirect(Float(s.monitorLevel))
        saveWav = s.saveWav
        ritHz = 0
        rit.ritHz = 0
        engine.configure(contestSettings())
    }

    /// The engine's view of the controls.
    func contestSettings() -> ContestSettings {
        var c = ContestSettings()
        c.myCallsign = myCallEdit.stringValue.trimmingCharacters(in: .whitespaces)
        c.wpm = wpmSpin.value
        c.pitchHz = PitchTable.hz(index: max(0, pitchCombo.indexOfSelectedItem))
        c.rxBandwidthHz = BandwidthTable.hz(index: max(0, bwCombo.indexOfSelectedItem))
        c.ritHz = ritHz
        c.qsk = qskCheck.state == .on
        c.qrn = qrnCheck.state == .on
        c.qrm = qrmCheck.state == .on
        c.qsb = qsbCheck.state == .on
        c.flutter = flutterCheck.state == .on
        c.lids = lidsCheck.state == .on
        c.activity = activitySpin.value
        c.durationMinutes = durationSpin.value
        c.selfMonGain01 = volume.value
        c.callsFromKeyer = callsFromKeyer
        return c
    }

    func showWindow() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(callEdit)
        installKeyPreview()
    }

    /// Removes what showWindow installed. Safe to call more than once.
    func teardown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        // FormClose; the app delegate stops the engine once on terminate.
        teardown()
        NSApp.terminate(nil)
    }

    func applyCaption() {
        window.title = Captions.windowTitle(hamName: hamName)
    }

    // MARK: - KeyPreview

    private func installKeyPreview() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, NSApp.modalWindow == nil else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    // MARK: - Station settings (Main.pas)

    /// SetPitch: Ini.Pitch := 300 + PitchNo·50.
    func setPitch(index: Int) {
        let i = PitchTable.clampedIndex(index)
        pitchCombo.selectItem(at: i)
        engine.setPitch(PitchTable.hz(index: i))
        settings.setPitchHz(PitchTable.hz(index: i))
    }

    /// SetBw: ignored outside the list; UpdateRitIndicator.
    func setBandwidth(index: Int) {
        guard BandwidthTable.isValid(index: index) else { return }
        bwCombo.selectItem(at: index)
        let hz = BandwidthTable.hz(index: index)
        engine.setBandwidth(hz)
        settings.setBandwidthHz(hz)
        rit.bandwidthHz = hz
    }

    @objc func pitchChanged() { setPitch(index: pitchCombo.indexOfSelectedItem) }
    @objc func bandwidthChanged() { setBandwidth(index: bwCombo.indexOfSelectedItem) }

    /// SpinEdit1Change.
    func wpmChanged(_ v: Int) {
        engine.setWpm(v)
        settings.setWpm(v)
    }

    /// SpinEdit3Change.
    func activityChanged(_ v: Int) {
        engine.setActivity(v)
        settings.setActivity(v)
    }

    /// SpinEdit2Change.
    func durationChanged(_ v: Int) {
        engine.setDuration(v)
        settings.setDurationMinutes(v)
    }

    /// VolumeSlider1Change (after the remap): the gain and Ini's
    /// SelfMonVolume.
    func monitorLevelChanged(_ v: Float) {
        engine.setMonitorLevel(v)
        settings.setMonitorLevel(Double(v))
    }

    /// SetQsk.
    func setQsk(_ on: Bool) {
        qskCheck.state = on ? .on : .off
        engine.setQsk(on)
        settings.setQsk(on)
    }

    @objc func qskClicked() {
        setQsk(qskCheck.state == .on)
        focus(.call)  // CheckBox1Click: ActiveControl := Edit1
    }

    /// ReadCheckboxes.
    func readCheckboxes() {
        let on = conditionChecks.map { $0.state == .on }
        engine.setConditions(qrn: on[0], qrm: on[1], qsb: on[2], flutter: on[3], lids: on[4])
        settings.setQrn(on[0])
        settings.setQrm(on[1])
        settings.setQsb(on[2])
        settings.setFlutter(on[3])
        settings.setLids(on[4])
    }

    @objc func conditionClicked() {
        readCheckboxes()
        focus(.call)
    }

    /// SetMyCall.
    func setMyCall(_ call: String) {
        myCallEdit.stringValue = call
        engine.setMyCall(call)
        settings.setMyCallsign(call)
    }

    /// IncRit.
    func incRit(_ step: Int) {
        setRit(Rit.step(ritHz, by: step))
    }

    /// Absolute RIT, from dragging the marker.
    func setRit(_ hz: Int) {
        ritHz = max(-Rit.limitHz, min(Rit.limitHz, hz))
        rit.ritHz = ritHz
        engine.setRit(ritHz)
    }

    func incSpeed() { wpmSpin.value = SpeedStep.up(wpmSpin.value) }
    func decSpeed() { wpmSpin.value = SpeedStep.down(wpmSpin.value) }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === myCallEdit {
            // Edit4Change: SetMyCall(Trim(Edit4.Text)).
            let call = myCallEdit.stringValue.trimmingCharacters(in: .whitespaces)
            engine.setMyCall(call)
            settings.setMyCallsign(call)
        } else if field === callEdit {
            apply(op.callEdited(callEdit.stringValue))  // Edit1Change
        }
    }

    // MARK: - Run (TMainForm.Run)

    func run(_ value: RunMode) {
        guard RunModeRules.shouldRun(value, current: runMode) else { return }
        let c = RunModeRules.controls(for: value, competitionDuration: competitionDuration)
        runMode = value
        applyRunControls(c)

        // WPX / HST force the conditions, the duration (and in HST the
        // activity and bandwidth) through the controls' change handlers,
        // so Ini keeps them (ToIni).
        if let on = c.forcedConditions {
            for cb in conditionChecks { cb.state = on ? .on : .off }
            readCheckboxes()
        }
        if let d = c.forcedDuration { durationSpin.value = d }
        if let a = c.forcedActivity { activitySpin.value = a }
        if let bw = c.forcedBandwidthIndex { setBandwidth(index: bw) }

        if c.resetsSession {
            runGeneration += 1
            log.clear()
            logView.reset(hst: value == .hst)
            var model = scoreTable.model
            model.reset(hst: value == .hst)
            scoreTable.model = model
            histogram.bins = HistogramGeometry.emptyBins
            apply(op.wipeBoxes(snapshot))
            logView.isHidden = false
            splash.isHidden = true
            incRit(0)
        }

        // AlWavFile1: overwrite at each Run when recording is enabled,
        // close at Stop.
        switch c.recording {
        case .close:
            engine.setRecording(nil)
        case .openIfEnabled:
            if saveWav {
                try? FileManager.default.createDirectory(at: files.baseDir, withIntermediateDirectories: true)
                engine.setRecording(files.recording)
            }
        }
        engine.setRunMode(value)
    }

    /// The enable / visibility part of Run, no side effects.
    func applyRunControls(_ c: RunControls) {
        let stop = c.mode == .stop
        myCallEdit.isEnabled = c.myCallEnabled
        durationSpin.isEnabled = c.durationEnabled
        runButton.setSelected(c.runButtonDown, forSegment: 0)
        for cb in conditionChecks { cb.isEnabled = c.conditionsEnabled }
        for i in runItems + popupRunItems { i.isEnabled = c.runItemsEnabled }
        stopItem.isEnabled = c.stopEnabled
        popupStopItem.isEnabled = c.stopEnabled
        callItem.isEnabled = c.myCallEnabled
        durationItem.isEnabled = c.durationEnabled
        for i in conditionItems { i.isEnabled = c.conditionsEnabled }
        activityItem.isEnabled = c.activityEnabled
        bandwidthItem.isEnabled = c.bandwidthEnabled
        activitySpin.isEnabled = c.activityEnabled
        bwCombo.isEnabled = c.bandwidthEnabled
        if let visible = c.scoreTableVisible { scoreTable.tableVisible = visible }
        modePanel.caption = c.caption
        modePanel.captionColor = Theme.color(c.captionColor)
        updateRunShortcuts(running: !stop)
    }
}
