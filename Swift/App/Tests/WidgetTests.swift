// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit
import MRAppCore
@testable import MorseRunner
import Testing

@MainActor
@Suite(.serialized)
struct WidgetTests {
    @Test func ritMouseHits() {
        let h = Harness()
        defer { h.cleanUp() }
        let r = h.controller.rit
        var steps: [Int] = []
        r.onStep = { steps.append($0) }
        let m = r.markerRect
        for p in [NSPoint(x: 3, y: 4), NSPoint(x: m.midX, y: 4), NSPoint(x: 220, y: 4),
                  NSPoint(x: m.midX, y: 0.5)] {
            r.mouseDown(with: h.mouse(.leftMouseDown, in: r, at: p))
            r.mouseUp(with: h.mouse(.leftMouseUp, in: r, at: p))
        }
        #expect(steps == [-1, 0, 1])
        #expect(r.accessibilityPerformIncrement())
        #expect(steps.last == 1)
        #expect(r.accessibilityRole() == .slider)
    }

    @Test func ritMarkerDrag() {
        let h = Harness()
        defer { h.cleanUp() }
        let c = h.controller
        let r = c.rit
        var steps: [Int] = []
        let wired = r.onStep
        r.onStep = { steps.append($0); wired?($0) }
        let m = r.markerRect
        let y = m.midY
        // Grab the marker and drag 11 px right: 99 Hz → 100 Hz.
        r.mouseDown(with: h.mouse(.leftMouseDown, in: r, at: NSPoint(x: m.midX, y: y)))
        r.mouseDragged(with: h.mouse(.leftMouseDragged, in: r, at: NSPoint(x: m.midX + 11, y: y)))
        #expect(c.ritHz == 100)
        #expect(r.ritHz == 100)
        // Further, past the limit, then back: tracks from the grab point.
        r.mouseDragged(with: h.mouse(.leftMouseDragged, in: r, at: NSPoint(x: m.midX + 200, y: y)))
        #expect(c.ritHz == 500)
        r.mouseDragged(with: h.mouse(.leftMouseDragged, in: r, at: NSPoint(x: m.midX - 6, y: y)))
        #expect(c.ritHz == -50)
        // Letting go after a drag keeps the value (no click reset).
        r.mouseUp(with: h.mouse(.leftMouseUp, in: r, at: NSPoint(x: m.midX - 6, y: y)))
        #expect(c.ritHz == -50)
        #expect(steps.isEmpty)
        // A press beside the marker steps and does not drag.
        r.mouseDown(with: h.mouse(.leftMouseDown, in: r, at: NSPoint(x: 3, y: y)))
        r.mouseDragged(with: h.mouse(.leftMouseDragged, in: r, at: NSPoint(x: 100, y: y)))
        r.mouseUp(with: h.mouse(.leftMouseUp, in: r, at: NSPoint(x: 100, y: y)))
        #expect(c.ritHz == -100)
        #expect(steps == [-1])
    }

    @Test func volumeSliderDoubleClickAndDrag() {
        let h = Harness()
        defer { h.cleanUp() }
        let v = h.controller.volume
        v.setValueDirect(0.5)
        var changes: [Float] = []
        v.onChange = { changes.append($0) }
        // A press off the thumb does not drag.
        v.mouseDown(with: h.mouse(.leftMouseDown, in: v, at: NSPoint(x: 55, y: 10)))
        v.mouseDragged(with: h.mouse(.leftMouseDragged, in: v, at: NSPoint(x: 58, y: 10)))
        #expect(changes.isEmpty)
        // On the thumb: +10 px of 50 = +0.2, then the Main.pas remap.
        let t = v.thumbRect
        v.mouseDown(with: h.mouse(.leftMouseDown, in: v, at: NSPoint(x: t.midX, y: t.midY)))
        v.mouseDragged(with: h.mouse(.leftMouseDragged, in: v, at: NSPoint(x: t.midX + 10, y: t.midY)))
        v.mouseUp(with: h.mouse(.leftMouseUp, in: v, at: NSPoint(x: t.midX + 10, y: t.midY)))
        #expect(changes.count == 1)
        #expect(abs(changes[0] - MonitorLevel.afterMainFormChange(0.7)) < 1e-6)
        v.mouseDown(with: h.mouse(.leftMouseDown, in: v, at: NSPoint(x: 5, y: 5), clicks: 2))
        #expect(changes.last == MonitorLevel.doubleClickValue)
        #expect(v.toolTip == "0 dB")
        #expect(v.accessibilityRole() == .slider)
    }

    @Test func scoreGridFitsItsFrame() {
        let h = Harness()
        defer { h.cleanUp() }
        let grid = h.controller.scoreTable.grid
        #expect(ScoreGridView.contentHeight <= grid.frame.height)
        #expect(grid.frame.height == 66)
        #expect(grid.accessibilityText.hasPrefix("Pts: raw 0, verified 0"))
    }

    @Test func histogramAccessibility() {
        let h = HistogramView(frame: NSRect(x: 0, y: 0, width: 223, height: 59))
        h.bins = [2, 3] + Array(repeating: 0, count: 46)
        #expect(h.accessibilityValue() as? String == "5 QSOs")
        #expect(h.accessibilityRole() == .image)
    }

    @Test(arguments: [
        (EntryFilter.call, "", NSRange(location: 0, length: 0), "k", "K", false),
        (EntryFilter.rst, "", NSRange(location: 0, length: 0), "t", "0", false),
        (EntryFilter.rst, "599", NSRange(location: 3, length: 0), "5999", "599", false),
        (EntryFilter.nr, "1", NSRange(location: 1, length: 0), "12", "12", true),
    ])
    func entryFormatterWrapper(_ f: EntryFilter, _ original: String, _ sel: NSRange, _ proposed: String,
                               _ result: String, _ valid: Bool) {
        let formatter = EntryFormatter(f)
        var partial = proposed as NSString
        var range = NSRange(location: (proposed as NSString).length, length: 0)
        let ok = formatter.isPartialStringValid(&partial, proposedSelectedRange: &range,
                                                originalString: original, originalSelectedRange: sel,
                                                errorDescription: nil)
        #expect(ok == valid)
        if valid {
            #expect(partial as String == proposed)
        } else if result == original {
            // Rejected: the pointer is left alone and AppKit keeps the original.
            #expect(partial as String == proposed)
        } else {
            #expect(partial as String == result)
        }
    }

    @Test func spinEditSilentSetterAndTyping() {
        let s = SpinEdit(frame: NSRect(x: 0, y: 0, width: 45, height: 22), range: .duration, value: 30,
                         label: "Duration")
        var fired: [Int] = []
        s.onChange = { fired.append($0) }
        s.setValueSilently(120)
        #expect(s.value == 120 && fired.isEmpty)
        s.value = 500
        #expect(s.value == 240 && fired == [240])
        s.field.stringValue = "15"
        s.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(fired.last == 15)
        s.field.stringValue = ""
        s.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
        #expect(s.field.stringValue == "15")
    }

    @Test func logViewReplacesOnlyItsOwnRow() {
        let v = LogView(frame: NSRect(x: 0, y: 0, width: 484, height: 280))
        v.reset(hst: false)
        v.appendRow(" 00:00:01  K1ABC         599 0001  599 0001  K1     NIL")
        v.replaceLastRow(" 00:00:01  K1ABC         599 0001  599 0001  K1        ")
        #expect(v.text.components(separatedBy: "\n").count == 2)
        v.showPlain("a\nb")
        v.replaceLastRow("row")
        #expect(v.text == "a\nb\nrow")
    }
}
