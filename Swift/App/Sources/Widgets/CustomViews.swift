// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Custom-drawn controls from Main.dfm. The geometry is MRAppCore's.

import AppKit
import MRAppCore

/// PaintBox1 — Log.pas PaintHisto: 48 bins of 5 minutes on clInfoBk,
/// clGreen bars on a 4-px stride, each bar 2·n + 1 px tall ending 2 px
/// above the bottom (empty bins draw a 1-px stub).
final class HistogramView: FlippedView {
    var bins: [Int] = HistogramGeometry.emptyBins {
        didSet {
            needsDisplay = true
            setAccessibilityValue("\(bins.reduce(0, +)) QSOs")
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("QSOs per 5 minutes")
        setAccessibilityValue("0 QSOs")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        Theme.clInfoBk.setFill()
        bounds.fill()
        Theme.clGreen.setFill()
        for b in HistogramGeometry.bars(bins, height: Int(bounds.height)) {
            NSRect(x: b.x, y: b.y, width: b.width, height: b.height).fill()
        }
    }
}

/// Panel8 + Shape2 — the RIT indicator. Clicking left / right of the
/// marker steps RIT by ∓50 Hz; clicking the marker resets it. Dragging the
/// marker sets RIT directly (a macOS addition; v1.68 has no drag).
final class RitView: FlippedView {
    var ritHz = 0 {
        didSet {
            needsDisplay = true
            setAccessibilityValue("\(ritHz) Hz")
        }
    }
    var bandwidthHz = 500 { didSet { needsDisplay = true } }
    /// -1, 0 or +1, as Pascal IncRit.
    var onStep: ((Int) -> Void)?
    /// An absolute RIT in Hz, while the marker is dragged.
    var onSet: ((Int) -> Void)?

    /// Set while the marker is held: where the press started and the RIT
    /// at that moment. `moved` tells a click (reset) from a drag.
    private var grab: (x: CGFloat, ritHz: Int, moved: Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("RIT")
        setAccessibilityValue("0 Hz")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var markerRect: NSRect {
        let m = Rit.marker(panelWidth: Int(bounds.width), panelHeight: Int(bounds.height),
                           bandwidthHz: bandwidthHz, ritHz: ritHz)
        return NSRect(x: m.x, y: m.y, width: m.width, height: m.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Panel8: BevelOuter = bvLowered.
        Theme.bevelShadow.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        Theme.bevelHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        // Shape2: rectangle, black pen, turquoise brush.
        let r = markerRect
        Theme.ritIndicator.setFill()
        r.fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        grab = nil
        guard let step = Rit.hit(x: Int(p.x.rounded(.down)), y: Int(p.y.rounded(.down)),
                                 panelWidth: Int(bounds.width), panelHeight: Int(bounds.height),
                                 bandwidthHz: bandwidthHz, ritHz: ritHz) else { return }
        if step == 0 {
            // On the marker: wait for mouse-up (reset) or a drag.
            grab = (p.x, ritHz, false)
        } else {
            onStep?(step)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var g = grab else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hz = Rit.dragged(from: g.ritHz, dx: Double(p.x - g.x))
        if p.x != g.x { g.moved = true }
        grab = g
        if hz != ritHz { onSet?(hz) }
    }

    override func mouseUp(with event: NSEvent) {
        // Shape2MouseDown: a plain click on the marker resets RIT.
        if let g = grab, !g.moved { onStep?(0) }
        grab = nil
    }

    override func accessibilityPerformIncrement() -> Bool {
        onStep?(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onStep?(-1)
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)  // crHandPoint
    }
}

/// VCL/VolmSldr.pas TVolumeSlider: a wedge with a thumb. Value 0..1.
/// Every user change goes through Main.pas's VolumeSlider1Change remap
/// (MonitorLevel.afterMainFormChange).
final class VolumeSlider: FlippedView {
    private(set) var value: Float = MonitorLevel.defaultValue
    private var downValue: Float = 0
    private var downX: CGFloat = 0
    private var dragging = false
    var isEnabled = true { didSet { needsDisplay = true } }
    /// Fired after the Main.pas remap, with the final Value.
    var onChange: ((Float) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Mon. Level")
        setValueDirect(MonitorLevel.defaultValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Set without the Main.pas remap (FromIni does this).
    func setValueDirect(_ v: Float) {
        value = MonitorLevel.clamp(v)
        toolTip = MonitorLevel.sliderHint(value: value)
        setAccessibilityValue(toolTip)
        needsDisplay = true
    }

    /// The value a user action produced (already remapped).
    private func userChanged(to v: Float) {
        value = v
        toolTip = MonitorLevel.mainFormHint(value: value)
        setAccessibilityValue(toolTip)
        needsDisplay = true
        onChange?(value)
    }

    /// Mon. Level menu (SelfMonClick).
    func selectMenuLevel(db tag: Int) {
        userChanged(to: MonitorLevel.menuValue(tag: tag))
    }

    var thumbRect: NSRect {
        let r = MonitorLevel.thumbRect(value: value, width: Int(bounds.width), height: Int(bounds.height))
        return NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    /// TVolumeSlider.Paint. GDI pens cover whole pixels and LineTo skips
    /// the end point, so straight edges are drawn as 1-px fills.
    override func draw(_ dirtyRect: NSRect) {
        // No background fill: the group box shows through, as clBtnFace
        // does under the original.
        let w = bounds.width, h = bounds.height
        let m = CGFloat(MonitorLevel.margin), vm = CGFloat(MonitorLevel.vMargin)
        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            NSRect(x: x, y: y, width: w, height: h).fill()
        }
        // Wedge body. Windows drew it on gray clBtnFace, where the white
        // edges below stand out; on the lighter macOS group box they
        // vanish, so fill the wedge to keep the ramp readable.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: m, y: h - vm))
        body.line(to: NSPoint(x: w - m + 1, y: h - vm))
        body.line(to: NSPoint(x: w - m + 1, y: vm))
        body.close()
        Theme.wedgeFill.setFill()
        body.fill()
        // Wedge: white bottom edge and right edge...
        Theme.bevelHighlight.setFill()
        px(m, h - vm, w - 2 * m, 1)
        px(w - m, vm + 1, 1, h - 2 * vm)
        // ...and a shadow hypotenuse from the top-right corner down to
        // the bottom-left (MoveTo/LineTo, pixel centres).
        NSGraphicsContext.current?.shouldAntialias = false
        let hyp = NSBezierPath()
        hyp.lineWidth = 1
        hyp.move(to: NSPoint(x: w - m + 0.5, y: vm + 0.5))
        hyp.line(to: NSPoint(x: m - 1 + 0.5, y: h - vm - 1 + 0.5))
        Theme.bevelShadow.setStroke()
        hyp.stroke()
        NSGraphicsContext.current?.shouldAntialias = true
        // Overload lamp: DrawEdge BDR_SUNKENOUTER | BF_MIDDLE, never lit.
        drawEdge(NSRect(x: m + 1, y: vm - 2, width: 7, height: 5), raised: false)
        // Thumb: DrawFrameControl DFCS_BUTTONPUSH when enabled, else a
        // sunken edge.
        let t = thumbRect
        if isEnabled {
            Theme.btnFace.setFill()
            t.fill()
            Theme.bevelHighlight.setFill()
            px(t.minX, t.minY, t.width - 1, 1)
            px(t.minX, t.minY, 1, t.height - 1)
            Theme.darkShadow.setFill()
            px(t.minX, t.maxY - 1, t.width, 1)
            px(t.maxX - 1, t.minY, 1, t.height)
            Theme.bevelShadow.setFill()
            px(t.minX + 1, t.maxY - 2, t.width - 2, 1)
            px(t.maxX - 2, t.minY + 1, 1, t.height - 2)
        } else {
            drawEdge(t, raised: false)
        }
    }

    private func drawEdge(_ r: NSRect, raised: Bool) {
        Theme.btnFace.setFill()
        r.fill()
        (raised ? Theme.bevelHighlight : Theme.bevelShadow).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        (raised ? Theme.bevelShadow : Theme.bevelHighlight).setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            // VolumeSliderDblClick.
            userChanged(to: MonitorLevel.doubleClickValue)
            return
        }
        if MonitorLevel.hitsThumb(x: Int(p.x.rounded(.down)), y: Int(p.y.rounded(.down)), value: value,
                                  width: Int(bounds.width), height: Int(bounds.height)) {
            dragging = true
            downValue = value
            downX = p.x
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        userChanged(to: MonitorLevel.dragValue(downValue: downValue, deltaX: Double(p.x - downX),
                                               width: Double(bounds.width)))
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        userChanged(to: MonitorLevel.dragValue(downValue: value, deltaX: 2.5, width: Double(bounds.width)))
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        userChanged(to: MonitorLevel.dragValue(downValue: value, deltaX: -2.5, width: Double(bounds.width)))
        return true
    }
}

/// RichEdit1: the log. Header underlined in blue; the 3-character error
/// tag at the end of each QSO row in red.
final class LogView: NSScrollView {
    private let textView = NSTextView()
    /// Whether the last line is a QSO row that the truth may replace.
    /// View Score Table mid-run replaces the text; Pascal's later
    /// Lines.Delete(Count-1) would then eat a score-list line (parity-
    /// checklist ◑): the port only replaces its own row.
    private(set) var lastLineIsQsoRow = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Theme.log
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: frame.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: frame.size)
        textView.setAccessibilityLabel("Log")
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var text: String { textView.string }

    private func setText(_ s: NSAttributedString) {
        textView.textStorage?.setAttributedString(s)
    }

    private func append(_ s: NSAttributedString) {
        textView.textStorage?.append(s)
    }

    private func attrs(_ color: NSColor = .black, underline: Bool = false)
        -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: Theme.log, .foregroundColor: color]
        if underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return a
    }

    /// Log.pas Clear: header line, underlined and blue.
    func reset(hst: Bool) {
        setText(NSAttributedString(string: Captions.logHeader(hst: hst),
                                   attributes: attrs(Theme.clBlue, underline: true)))
        lastLineIsQsoRow = false
    }

    /// LastQsoToScreen; the last 3 characters (the error tag) in red.
    func appendRow(_ row: String) {
        let (body, tag) = Captions.splitLogRow(row)
        append(NSAttributedString(string: "\n" + body, attributes: attrs()))
        append(NSAttributedString(string: tag, attributes: attrs(Theme.clRed)))
        lastLineIsQsoRow = true
        textView.scrollToEndOfDocument(nil)
    }

    /// RichEdit1.Lines.Delete(Count - 1), then LastQsoToScreen.
    func replaceLastRow(_ row: String) {
        let s = textView.string as NSString
        let lastBreak = s.range(of: "\n", options: .backwards)
        guard lastLineIsQsoRow, lastBreak.location != NSNotFound else {
            appendRow(row)
            return
        }
        textView.textStorage?.deleteCharacters(in: NSRange(location: lastBreak.location,
                                                           length: s.length - lastBreak.location))
        appendRow(row)
    }

    /// File › View Score Table.
    func showPlain(_ text: String) {
        setText(NSAttributedString(string: text, attributes: attrs()))
        lastLineIsQsoRow = false
        textView.scrollToBeginningOfDocument(nil)
    }
}

/// Panel6 before the first run: Shape1 background, the three-layer
/// "Morse Runner 1.68" logo and the copyright / FREEWARE labels.
final class SplashView: FlippedView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.logBackground.setFill()
        bounds.fill()
        let title = "Morse Runner 1.68"
        for (dx, dy, color) in [(76.0, 60.0, Theme.logoShadow), (71.0, 56.0, Theme.clAqua),
                                (70.0, 55.0, Theme.clGreen)] {
            NSAttributedString(string: title, attributes: [.font: Theme.logo,
                                                           .foregroundColor: color])
                .draw(at: NSPoint(x: dx, y: dy))
        }
        let a: [NSAttributedString.Key: Any] = [.font: Theme.base, .foregroundColor: NSColor.black]
        let copyright = NSAttributedString(string: "Copyright © 2004-2006 Alex Shovkoplyas, VE3NEA",
                                           attributes: a)
        copyright.draw(at: NSPoint(x: 106, y: 108))
        NSAttributedString(string: "FREEWARE", attributes: a).draw(at: NSPoint(x: 198, y: 128))
        // Port credit (not in v1.68), centred under the copyright line.
        let credit = NSAttributedString(string: "Ported to macOS by Mike, KF5O", attributes: a)
        let centre = 106 + copyright.size().width / 2
        credit.draw(at: NSPoint(x: (centre - credit.size().width / 2).rounded(), y: 148))
    }
}
