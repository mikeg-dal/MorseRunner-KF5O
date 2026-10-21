// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MainMenu1 and PopupMenu1 (items from MRAppCore.MenuSpec) and their
// handlers. The application, Edit and Window menus are macOS additions
// (parity-checklist ◑): the standard items text fields expect.

import AppKit
import MRAppCore
import MRPersistence
import MRSimulation

extension MainWindowController {
    private func keyEquivalent(_ s: MenuShortcut) -> String {
        Unicode.Scalar(s.key).map { String(Character($0)) } ?? ""
    }

    func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func sub(_ title: String, _ menu: NSMenu? = nil) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = menu ?? NSMenu(title: title)
            item.submenu = m
            main.addItem(item)
            return m
        }
        @discardableResult
        func item(_ m: NSMenu, _ title: String, _ action: Selector?, key: String = "",
                  mods: NSEvent.ModifierFlags = [], tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.tag = tag
            m.addItem(i)
            return i
        }
        /// Standard items: no target, so they go to the responder chain.
        func std(_ m: NSMenu, _ title: String, _ action: Selector, _ key: String,
                 mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            m.addItem(i)
        }

        // Application menu (macOS).
        let app = sub("Morse Runner")
        item(app, "About Morse Runner", #selector(about))
        app.addItem(.separator())
        std(app, "Hide Morse Runner", #selector(NSApplication.hide(_:)), "h")
        std(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            mods: [.command, .option])
        std(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)), "")
        app.addItem(.separator())
        std(app, "Quit Morse Runner", #selector(NSApplication.terminate(_:)), "q")

        let file = sub("File", fileMenu)
        file.delegate = self  // File1Click refreshes the recording items
        item(file, "View Score Table", #selector(viewScoreTable))
        item(file, "View Hi-Score web page...", #selector(viewHiScorePage))
        file.addItem(.separator())
        audioRecordingItem = item(file, "Audio Recording Enabled", #selector(toggleRecording))
        playRecordingItem = item(file, "Play Recorded Audio", #selector(playRecording))
        file.addItem(.separator())
        let exit = item(file, "Exit", #selector(NSApplication.terminate(_:)))
        exit.target = nil

        // Edit (macOS): Cut / Copy / Paste for the text fields.
        let edit = sub("Edit")
        std(edit, "Undo", Selector(("undo:")), "z")
        std(edit, "Redo", Selector(("redo:")), "Z")
        edit.addItem(.separator())
        std(edit, "Cut", #selector(NSText.cut(_:)), "x")
        std(edit, "Copy", #selector(NSText.copy(_:)), "c")
        std(edit, "Paste", #selector(NSText.paste(_:)), "v")
        std(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        let run = sub("Run")
        runItems = MenuSpec.runItems.map { r in
            let i = item(run, r.title, #selector(runMenu(_:)), tag: r.mode.rawValue)
            if let sc = r.shortcut {
                i.keyEquivalent = keyEquivalent(sc)
                i.keyEquivalentModifierMask = sc.control ? [.control] : []
            }
            return i
        }
        run.addItem(.separator())
        stopItem = item(run, "Stop", #selector(stopMenu))

        // PopupMenu1 on the Run button; Pile-Up is its default (bold) item.
        popupRunItems = MenuSpec.runItems.map { item(runPopup, $0.title, #selector(runMenu(_:)), tag: $0.mode.rawValue) }
        if let first = popupRunItems.first {
            first.attributedTitle = NSAttributedString(
                string: first.title,
                attributes: [.font: NSFontManager.shared.convert(NSFont.menuFont(ofSize: 0),
                                                                 toHaveTrait: .boldFontMask)])
        }
        runPopup.addItem(.separator())
        popupStopItem = item(runPopup, "Stop", #selector(stopMenu))

        let send = sub("Send")
        sendItems = MenuSpec.sendItems.map {
            item(send, $0.title, #selector(sendMenu(_:)), key: keyEquivalent($0.shortcut), tag: $0.message.rawValue)
        }

        let set = sub("Settings", settingsMenu)
        callItem = item(set, "Call...", #selector(callMenu))
        qskItem = item(set, "QSK", #selector(qskMenu))
        let speed = NSMenu()
        for w in MenuSpec.speeds { item(speed, "\(w) WPM", #selector(speedMenu(_:)), tag: w) }
        set.addItem(withTitle: "CW Speed", action: nil, keyEquivalent: "").submenu = speed
        let pitch = NSMenu()
        for (i, t) in PitchTable.titles.enumerated() { item(pitch, t, #selector(pitchMenu(_:)), tag: i) }
        set.addItem(withTitle: "CW Pitch", action: nil, keyEquivalent: "").submenu = pitch
        let bw = NSMenu()
        for (i, t) in BandwidthTable.titles.enumerated() { item(bw, t, #selector(bandwidthMenu(_:)), tag: i) }
        bandwidthItem = set.addItem(withTitle: "CW Bandwidth", action: nil, keyEquivalent: "")
        bandwidthItem.submenu = bw
        let mon = NSMenu()
        for l in MenuSpec.monitorLevels { item(mon, l.title, #selector(monMenu(_:)), tag: l.tag) }
        set.addItem(withTitle: "Mon. Level", action: nil, keyEquivalent: "").submenu = mon
        set.addItem(.separator())
        conditionItems = MenuSpec.conditions.map { item(set, $0, #selector(conditionMenu(_:))) }
        let act = NSMenu()
        for a in MenuSpec.activities { item(act, "\(a)", #selector(activityMenu(_:)), tag: a) }
        activityItem = set.addItem(withTitle: "Activity", action: nil, keyEquivalent: "")
        activityItem.submenu = act
        set.addItem(.separator())
        let dur = NSMenu()
        for m in MenuSpec.durations { item(dur, "\(m) min", #selector(durationMenu(_:)), tag: m) }
        durationItem = set.addItem(withTitle: "Duration", action: nil, keyEquivalent: "")
        durationItem.submenu = dur
        item(set, "HST Operator...", #selector(operatorMenu))
        set.delegate = self  // Settings1Click refreshes the check marks

        // Window (macOS).
        let window = sub("Window", windowsMenu)
        std(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        window.addItem(.separator())
        std(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")

        let help = sub("Help")
        item(help, "Web Page...", #selector(webPage))
        item(help, "Readme...", #selector(readme))
        help.addItem(.separator())
        item(help, "About...", #selector(about))

        // Main.pas enables these menus' items itself (Run, File1Click).
        for m in [file, run, send, set, help, runPopup] { m.autoenablesItems = false }
        return main
    }

    /// F8 belongs to Run › Pile-Up while stopped and to Send › NIL during
    /// a run (MenuSpec.shortcutOwner).
    func updateRunShortcuts(running: Bool) {
        for (item, spec) in zip(runItems, MenuSpec.runItems) {
            guard let sc = spec.shortcut else { continue }
            item.keyEquivalent = MenuSpec.runShortcutActive(spec, running: running) ? keyEquivalent(sc) : ""
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === fileMenu {
            // File1Click.
            let stopped = runMode == .stop
            audioRecordingItem.isEnabled = stopped
            playRecordingItem.isEnabled = stopped && files.recordingExists
            audioRecordingItem.state = saveWav ? .on : .off
        } else if menu === settingsMenu {
            // Settings1Click.
            qskItem.state = qskCheck.state
            for (item, cb) in zip(conditionItems, conditionChecks) { item.state = cb.state }
        }
    }

    // MARK: - Actions

    @objc func runMenu(_ sender: NSMenuItem) {
        run(RunMode(rawValue: sender.tag) ?? .pileUp)
    }

    /// StopMNUClick: Tst.FStopPressed := true.
    @objc func stopMenu() { engine.requestStop() }

    /// RunBtnClick (segment 0); segment 1 only shows the popup.
    @objc func runButtonClicked() {
        if runButton.selectedSegment == 0 || runButton.isSelected(forSegment: 0) != (runMode != .stop) {
            if runMode == .stop {
                run(.pileUp)
            } else {
                engine.requestStop()
            }
        }
        runButton.setSelected(runMode != .stop, forSegment: 0)
        runButton.setSelected(false, forSegment: 1)
    }

    /// SendClick.
    @objc func sendMenu(_ sender: NSMenuItem) {
        apply(op.send(Message(rawValue: sender.tag) ?? .cq, snapshot))
    }

    @objc func fKeyClicked(_ sender: NSButton) {
        apply(op.send(Message(rawValue: sender.tag) ?? .cq, snapshot))
    }

    /// Call1Click: SetMyCall(Trim(InputBox('Callsign', 'Callsign', Edit4.Text))).
    @objc func callMenu() {
        if let v = Dialogs.inputBox("Callsign", "Callsign", myCallEdit.stringValue) {
            setMyCall(EntryFilter.myCall.clean(v.trimmingCharacters(in: .whitespaces)))
        }
    }

    /// QSK1Click.
    @objc func qskMenu() { setQsk(qskCheck.state != .on) }

    /// NWPMClick.
    @objc func speedMenu(_ sender: NSMenuItem) { wpmSpin.value = SpeedStep.clamp(sender.tag) }
    @objc func pitchMenu(_ sender: NSMenuItem) { setPitch(index: sender.tag) }
    @objc func bandwidthMenu(_ sender: NSMenuItem) { setBandwidth(index: sender.tag) }
    @objc func monMenu(_ sender: NSMenuItem) { volume.selectMenuLevel(db: sender.tag) }

    /// LIDS1Click: toggle the item, copy all five to the checkboxes.
    @objc func conditionMenu(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        for (cb, item) in zip(conditionChecks, conditionItems) { cb.state = item.state }
        readCheckboxes()
    }

    @objc func activityMenu(_ sender: NSMenuItem) { activitySpin.value = sender.tag }
    @objc func durationMenu(_ sender: NSMenuItem) { durationSpin.value = sender.tag }

    /// Operator1Click.
    @objc func operatorMenu() {
        if let name = Dialogs.inputBox("HST Operator", "Enter operator's name", hamName) {
            hamName = name
            applyCaption()
            settings.setHamName(name)
        }
    }

    @objc func viewHiScorePage() {
        if let url = URL(string: MenuSpec.hiScoreURL) { openURL(url) }
    }

    @objc func webPage() {
        if let url = URL(string: MenuSpec.webPageURL) { openURL(url) }
    }

    @objc func readme() {
        if let url = Bundle.main.url(forResource: "Readme", withExtension: "txt") { openURL(url) }
    }

    @objc func about() { Dialogs.about() }
}
