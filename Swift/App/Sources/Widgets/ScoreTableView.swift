// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit
import MRAppCore

/// Panel11 + ListView1: Pts / Mult / Score × Raw / Verified. In HST the
/// list is hidden and Panel11's own caption (bold 19 px) shows the score.
final class ScoreTableView: FlippedView {
    private let panel = BevelPanel()
    let grid = ScoreGridView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        panel.frame = bounds
        panel.outer = .lowered
        panel.caption = "0"
        panel.captionFont = Theme.hstScore
        addSubview(panel)
        // ListView1: alClient inside Panel11's 1-px bevel, BorderStyle bsNone.
        grid.frame = bounds.insetBy(dx: 1, dy: 1)
        addSubview(grid)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// ListView1's cells and Panel11's caption.
    var model = ScoreTableModel() {
        didSet {
            grid.cells = model.cells
            panel.caption = model.hstCaption
        }
    }

    var tableVisible: Bool {
        get { !grid.isHidden }
        set { grid.isHidden = !newValue }
    }

    var hstCaption: String { panel.caption }
}

/// ListView1 in vsReport style, drawn directly: an NSTableView's header
/// is too tall for the 66-px space and pushed the Score row out of view.
final class ScoreGridView: FlippedView {
    /// Column widths from Main.dfm (Raw/Verified use the VCL default 50).
    private let widths: [CGFloat] = [41, 50, 50]
    private let titles = ScoreTableModel.columnTitles
    private let rowNames = ScoreTableModel.rowTitles
    static let headerHeight: CGFloat = 17
    static let rowHeight: CGFloat = 15
    private var headerHeight: CGFloat { Self.headerHeight }
    private var rowHeight: CGFloat { Self.rowHeight }
    /// cells[row][col], col 0 = Raw, 1 = Verified.
    var cells = ScoreTableModel().cells {
        didSet {
            needsDisplay = true
            updateAccessibility()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Score")
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// "Pts: raw 3, verified 2; ..." for VoiceOver.
    var accessibilityText: String {
        zip(rowNames, cells).map { name, row in
            "\(name): raw \(row[0].isEmpty ? "-" : row[0]), verified \(row[1].isEmpty ? "-" : row[1])"
        }.joined(separator: "; ")
    }

    private func updateAccessibility() { setAccessibilityValue(accessibilityText) }

    /// Bottom of the last row.
    static var contentHeight: CGFloat { headerHeight + 3 * rowHeight }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()  // clWindow
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.base, .foregroundColor: NSColor.black,
        ]
        func text(_ s: String, x: CGFloat, y: CGFloat, h: CGFloat, w: CGFloat) {
            let size = (s as NSString).size(withAttributes: attrs)
            let r = NSRect(x: x, y: y + ((h - size.height) / 2).rounded(), width: w, height: size.height)
            (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: attrs)
        }

        // Header: one raised button face per column, then the empty
        // remainder (also a header face, as Windows draws it).
        var x: CGFloat = 0
        for (i, w) in (widths + [max(0, bounds.width - widths.reduce(0, +))]).enumerated() {
            let r = NSRect(x: x, y: 0, width: w, height: headerHeight)
            Theme.btnFace.setFill()
            r.fill()
            Theme.bevelHighlight.setFill()
            NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: 1).fill()
            NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
            Theme.bevelShadow.setFill()
            NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
            NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
            if i < titles.count, !titles[i].isEmpty {
                text(titles[i], x: r.minX + 6, y: 0, h: headerHeight, w: r.width - 8)
            }
            x += w
        }

        // Rows: item caption 2 px in, sub-items 6 px in.
        for row in 0..<3 {
            let y = headerHeight + CGFloat(row) * rowHeight
            text(rowNames[row], x: 2, y: y, h: rowHeight, w: widths[0] - 4)
            text(cells[row][0], x: widths[0] + 6, y: y, h: rowHeight, w: widths[1] - 8)
            text(cells[row][1], x: widths[0] + widths[1] + 6, y: y, h: rowHeight, w: widths[2] - 8)
        }
    }
}
