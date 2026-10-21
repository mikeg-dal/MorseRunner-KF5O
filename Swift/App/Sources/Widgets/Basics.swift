// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Small building blocks that stand in for VCL controls.

import AppKit
import MRAppCore

/// Top-left origin, like VCL, so Main.dfm coordinates can be used as-is.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// TPanel / TBevel look: optional outer and inner 1-px bevels, optional
/// background colour and centred caption.
final class BevelPanel: FlippedView {
    enum Bevel { case none, lowered, raised }
    var outer: Bevel = .lowered { didSet { needsDisplay = true } }
    var inner: Bevel = .none { didSet { needsDisplay = true } }
    var fill: NSColor? { didSet { needsDisplay = true } }
    var caption = "" {
        didSet {
            needsDisplay = true
            setAccessibilityElement(!caption.isEmpty)
            setAccessibilityRole(.staticText)
            setAccessibilityValue(caption)
        }
    }
    var captionFont: NSFont = Theme.base { didSet { needsDisplay = true } }
    var captionColor: NSColor = .labelColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        if let fill {
            fill.setFill()
            bounds.fill()
        }
        var r = bounds
        drawBevel(outer, in: r)
        if outer != .none { r = r.insetBy(dx: 1, dy: 1) }
        drawBevel(inner, in: r)
        if !caption.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: captionFont,
                                                        .foregroundColor: captionColor]
            let s = NSAttributedString(string: caption, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                               y: (bounds.height - size.height) / 2))
        }
    }

    private func drawBevel(_ b: Bevel, in r: NSRect) {
        guard b != .none else { return }
        let (topLeft, bottomRight) = b == .lowered
            ? (Theme.bevelShadow, Theme.bevelHighlight)
            : (Theme.bevelHighlight, Theme.bevelShadow)
        topLeft.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        bottomRight.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }
}

/// VCL TLabel at Main.dfm coordinates.
@MainActor
func makeLabel(_ text: String, _ frame: NSRect, font: NSFont = Theme.base) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.frame = frame
    return l
}

/// NSFormatter face of MRAppCore.EntryFilter (CharCase / OnKeyPress /
/// MaxLength).
nonisolated final class EntryFormatter: Formatter {
    let filter: EntryFilter

    init(_ filter: EntryFilter) {
        self.filter = filter
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partial: AutoreleasingUnsafeMutablePointer<NSString>,
                                       proposedSelectedRange: NSRangePointer?,
                                       originalString: String,
                                       originalSelectedRange: NSRange,
                                       errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        switch filter.filter(original: originalString, selection: originalSelectedRange,
                             proposed: partial.pointee as String) {
        case .accept:
            return true
        case .reject:
            return false
        case .replace(let text, let caret):
            partial.pointee = text as NSString
            proposedSelectedRange?.pointee = NSRange(location: caret, length: 0)
            return false
        }
    }
}

/// A TEdit that reports OnEnter (every focus change into it).
final class EntryTextField: NSTextField {
    var onEnter: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            // AutoSelect = False: no select-all on entry; OnEnter may then
            // select something itself.
            if let editor = currentEditor() {
                editor.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
            }
            onEnter?()
        }
        return ok
    }
}

/// VCL TSpinEdit: a number field with up/down arrows.
final class SpinEdit: FlippedView, NSTextFieldDelegate {
    let field = NSTextField()
    let stepper = NSStepper()
    let range: SpinRange
    /// SpinEditNChange; fired by user input and by `value`'s setter.
    var onChange: ((Int) -> Void)?

    var value: Int {
        get { stepper.integerValue }
        set {
            let v = range.clamp(newValue)
            let changed = v != stepper.integerValue || field.stringValue != String(v)
            setValueSilently(v)
            if changed { onChange?(v) }
        }
    }

    /// Shows `v` without firing onChange (FromIni pushes the engine and
    /// the defaults itself).
    func setValueSilently(_ v: Int) {
        let c = range.clamp(v)
        stepper.integerValue = c
        field.stringValue = String(c)
        setAccessibilityValue(String(c))
    }

    var isEnabled: Bool {
        get { field.isEnabled }
        set {
            field.isEnabled = newValue
            stepper.isEnabled = newValue
        }
    }

    init(frame: NSRect, range: SpinRange, value: Int, label: String) {
        self.range = range
        super.init(frame: frame)
        let stepW: CGFloat = 13
        field.frame = NSRect(x: 0, y: 0, width: frame.width - stepW, height: frame.height)
        field.font = Theme.base
        field.controlSize = .small
        field.alignment = .left
        field.formatter = EntryFormatter(.digits(maxLength: range.maxLength))
        field.delegate = self
        field.setAccessibilityLabel(label)
        stepper.frame = NSRect(x: frame.width - stepW, y: 0, width: stepW, height: frame.height)
        stepper.controlSize = .small
        stepper.minValue = Double(range.min)
        stepper.maxValue = Double(range.max)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepped)
        stepper.refusesFirstResponder = true  // TabStop = False on the original's spins
        stepper.setAccessibilityLabel(label)
        addSubview(field)
        addSubview(stepper)
        setValueSilently(value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func stepped() {
        field.stringValue = String(stepper.integerValue)
        onChange?(stepper.integerValue)
    }

    func controlTextDidChange(_ obj: Notification) {
        // Applied as typed, once the text is a value in range.
        guard let v = range.typedValue(field.stringValue), v != stepper.integerValue else { return }
        stepper.integerValue = v
        onChange?(v)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // CMExit: clamp into range.
        value = range.committedValue(field.stringValue, current: stepper.integerValue)
    }
}
