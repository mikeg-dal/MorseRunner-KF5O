// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Main.dfm's layout, at its own coordinates.

import AppKit
import MRAppCore
import MRSimulation

extension MainWindowController {
    func buildLayout() {
        // Bevel1 (alTop, 2 px).
        let bevel1 = BevelPanel(frame: NSRect(x: 0, y: 0, width: 700, height: 2))
        bevel1.outer = .lowered
        root.addSubview(bevel1)

        // Panel6 (alClient, BorderStyle bsSingle): splash, then the log.
        let panel6 = BevelPanel(frame: NSRect(x: 0, y: 2, width: 488, height: 284))
        panel6.outer = .lowered
        panel6.inner = .lowered
        root.addSubview(panel6)
        splash.frame = NSRect(x: 2, y: 2, width: 484, height: 280)
        logView.frame = splash.frame
        logView.isHidden = true  // RichEdit1.Visible = False until Run / View Score
        panel6.addSubview(splash)
        panel6.addSubview(logView)

        buildRightPanel()
        buildBottomPanel()
    }

    private func groupBox(_ title: String, _ frame: NSRect) -> FlippedView {
        let box = NSBox(frame: frame)
        box.title = title
        box.titleFont = Theme.base
        box.boxType = .primary
        let panel9Origin = NSPoint(x: 488, y: 2)
        root.addSubview(box)
        box.frame = frame.offsetBy(dx: panel9Origin.x, dy: panel9Origin.y)
        // Children use GroupBox coordinates; an overlay keeps them exact.
        let overlay = FlippedView(frame: box.frame)
        root.addSubview(overlay)
        return overlay
    }

    private func buildRightPanel() {
        // GroupBox1 " Station "
        let g1 = groupBox(" Station ", NSRect(x: 9, y: 6, width: 194, height: 159))
        g1.addSubview(makeLabel("Call", NSRect(x: 12, y: 20, width: 24, height: 14)))
        myCallEdit.frame = NSRect(x: 36, y: 16, width: 89, height: 21)
        myCallEdit.font = Theme.base
        myCallEdit.formatter = EntryFormatter(.myCall)
        myCallEdit.delegate = self
        myCallEdit.setAccessibilityLabel("My call")
        g1.addSubview(myCallEdit)
        qskCheck.frame = NSRect(x: 140, y: 18, width: 50, height: 17)
        qskCheck.font = Theme.base
        qskCheck.controlSize = .small
        qskCheck.target = self
        qskCheck.action = #selector(qskClicked)
        qskCheck.refusesFirstResponder = true
        g1.addSubview(qskCheck)
        g1.addSubview(makeLabel("CW Speed", NSRect(x: 12, y: 48, width: 60, height: 14)))
        g1.addSubview(wpmSpin)
        g1.addSubview(makeLabel("WPM", NSRect(x: 156, y: 48, width: 30, height: 14)))
        wpmSpin.onChange = { [weak self] v in self?.wpmChanged(v) }

        g1.addSubview(makeLabel("CW Pitch", NSRect(x: 12, y: 76, width: 60, height: 14)))
        // ComboBox1/2 are 65 px in Main.dfm; a small NSPopUpButton needs 78
        // to show "900 Hz" without truncating.
        pitchCombo.frame = NSRect(x: 88, y: 72, width: 78, height: 21)
        configureCombo(pitchCombo, titles: PitchTable.titles, action: #selector(pitchChanged))
        pitchCombo.setAccessibilityLabel("CW Pitch")
        g1.addSubview(pitchCombo)
        g1.addSubview(makeLabel("RX Bandwidth", NSRect(x: 12, y: 104, width: 74, height: 14)))
        bwCombo.frame = NSRect(x: 88, y: 100, width: 78, height: 21)
        configureCombo(bwCombo, titles: BandwidthTable.titles, action: #selector(bandwidthChanged))
        bwCombo.setAccessibilityLabel("RX Bandwidth")
        g1.addSubview(bwCombo)
        g1.addSubview(makeLabel("Mon. Level", NSRect(x: 12, y: 134, width: 60, height: 14)))
        volume.onChange = { [weak self] v in self?.monitorLevelChanged(v) }
        g1.addSubview(volume)

        // GroupBox3 " Band Conditions "
        let g3 = groupBox(" Band Conditions ", NSRect(x: 9, y: 170, width: 194, height: 81))
        for (cb, frame) in zip(conditionChecks, [NSRect(x: 12, y: 18, width: 50, height: 17),
                                                 NSRect(x: 12, y: 38, width: 50, height: 17),
                                                 NSRect(x: 12, y: 58, width: 50, height: 17),
                                                 NSRect(x: 76, y: 18, width: 60, height: 17),
                                                 NSRect(x: 76, y: 40, width: 55, height: 17)]) {
            cb.frame = frame
            cb.font = Theme.base
            cb.controlSize = .small
            cb.target = self
            cb.action = #selector(conditionClicked)
            cb.refusesFirstResponder = true
            g3.addSubview(cb)
        }
        g3.addSubview(makeLabel("Activity", NSRect(x: 144, y: 16, width: 44, height: 14)))
        g3.addSubview(activitySpin)
        activitySpin.onChange = { [weak self] v in self?.activityChanged(v) }

        // Panel10: Run button + "for N min."
        let p10 = FlippedView(frame: NSRect(x: 488, y: 2 + 253, width: 212, height: 31))
        root.addSubview(p10)
        runButton.segmentCount = 2
        runButton.setLabel("   Run   ", forSegment: 0)
        runButton.setWidth(60, forSegment: 0)
        runButton.setLabel("", forSegment: 1)
        runButton.setWidth(18, forSegment: 1)
        runButton.setMenu(runPopup, forSegment: 1)
        runButton.setShowsMenuIndicator(true, forSegment: 1)
        runButton.trackingMode = .selectAny
        runButton.font = Theme.base
        runButton.controlSize = .small
        runButton.frame = NSRect(x: 13, y: 5, width: 84, height: 24)
        runButton.target = self
        runButton.action = #selector(runButtonClicked)
        runButton.refusesFirstResponder = true
        runButton.setAccessibilityLabel("Run")
        p10.addSubview(runButton)
        p10.addSubview(makeLabel("for", NSRect(x: 103, y: 9, width: 18, height: 14)))
        p10.addSubview(durationSpin)
        durationSpin.onChange = { [weak self] v in self?.durationChanged(v) }
        p10.addSubview(makeLabel("min.", NSRect(x: 170, y: 9, width: 30, height: 14)))
    }

    private func configureCombo(_ c: NSPopUpButton, titles: [String], action: Selector) {
        c.removeAllItems()
        c.addItems(withTitles: titles)
        c.font = Theme.base
        c.controlSize = .small
        c.target = self
        c.action = action
        c.refusesFirstResponder = true
    }

    private func buildBottomPanel() {
        // Panel5 spacer (8 px), then Panel1 (alBottom, 119 px).
        let p1 = BevelPanel(frame: NSRect(x: 0, y: 294, width: 700, height: 119))
        p1.outer = .lowered
        p1.inner = .raised
        root.addSubview(p1)

        p1.addSubview(makeLabel("Call", NSRect(x: 16, y: 12, width: 30, height: 14)))
        p1.addSubview(makeLabel("RST", NSRect(x: 172, y: 12, width: 30, height: 14)))
        p1.addSubview(makeLabel("Nr.", NSRect(x: 224, y: 12, width: 24, height: 14)))
        let fields: [(EntryTextField, NSRect, EntryFilter, EntryField, String)] = [
            (callEdit, NSRect(x: 12, y: 28, width: 149, height: 28), .call, .call, "Call"),
            // Deviation from v1.68 (Edit2/Edit3KeyPress drop any non-digit):
            // cut numbers as heard are typed straight in, T/O -> 0, N -> 9.
            (rstEdit, NSRect(x: 168, y: 28, width: 45, height: 28), .rst, .rst, "RST"),
            (nrEdit, NSRect(x: 220, y: 28, width: 45, height: 28), .nr, .nr, "Nr."),
        ]
        for (edit, frame, filter, which, label) in fields {
            edit.frame = frame
            edit.font = Theme.entry
            edit.formatter = EntryFormatter(filter)
            edit.delegate = self
            edit.bezelStyle = .squareBezel
            edit.setAccessibilityLabel(label)
            edit.onEnter = { [weak self] in self?.entryFocused(which) }
            p1.addSubview(edit)
        }
        // Tab order Edit1 → Edit2 → Edit3 (the right panel has TabStop off).
        callEdit.nextKeyView = rstEdit
        rstEdit.nextKeyView = nrEdit
        nrEdit.nextKeyView = callEdit

        for (i, s) in MenuSpec.sendItems.enumerated() {
            let b = NSButton(title: s.buttonCaption, target: self, action: #selector(fKeyClicked(_:)))
            b.tag = s.message.rawValue
            b.bezelStyle = .smallSquare
            b.font = Theme.base
            b.controlSize = .small
            b.refusesFirstResponder = true  // SpeedButtons never take focus
            b.frame = NSRect(x: 12 + (i % 4) * 64, y: i < 4 ? 68 : 92, width: 61, height: 17)
            p1.addSubview(b)
            fKeys.append(b)
        }
        let bevel2 = BevelPanel(frame: NSRect(x: 277, y: 6, width: 2, height: 107))
        bevel2.outer = .lowered
        p1.addSubview(bevel2)

        modePanel.frame = NSRect(x: 292, y: 8, width: 114, height: 21)
        modePanel.captionFont = Theme.baseBold
        modePanel.captionColor = Theme.clRed
        modePanel.setAccessibilityLabel("Mode")
        p1.addSubview(modePanel)
        ratePanel.frame = NSRect(x: 412, y: 8, width: 104, height: 21)
        ratePanel.setAccessibilityLabel("Rate")
        p1.addSubview(ratePanel)
        clockPanel.frame = NSRect(x: 529, y: 8, width: 163, height: 31)
        clockPanel.fill = .black
        clockPanel.caption = Captions.clock(seconds: 0)
        clockPanel.captionFont = Theme.clock
        clockPanel.captionColor = Theme.clockText
        clockPanel.setAccessibilityLabel("Contest time")
        p1.addSubview(clockPanel)
        let p3 = BevelPanel(frame: NSRect(x: 292, y: 35, width: 225, height: 61))
        p3.addSubview(histogram)
        p1.addSubview(p3)
        rit.toolTip = "RIT"
        rit.onStep = { [weak self] step in self?.incRit(step) }
        rit.onSet = { [weak self] hz in self?.setRit(hz) }
        p1.addSubview(rit)
        p1.addSubview(scoreTable)
    }
}
