// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit

enum Dialogs {
    /// Delphi InputBox(caption, prompt, default). Returns nil on Cancel.
    @MainActor
    static func inputBox(_ caption: String, _ prompt: String, _ value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = caption
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// About1Click: Application.MessageBox(Msg, 'Morse Runner 1.68').
    @MainActor
    static func about() {
        let alert = NSAlert()
        alert.messageText = "Morse Runner 1.68"
        alert.informativeText = "CW CONTEST SIMULATOR\n\nCopyright © 2004-2006 Alex Shovkoplyas, VE3NEA\n\nve3nea@dxatlas.com\n\nmacOS port © 2026 Mike Garcia, KF5O. Mozilla Public License 2.0."
        alert.alertStyle = .informational
        alert.runModal()
    }

    /// ShowMessage(text).
    @MainActor
    static func message(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Morse Runner"
        alert.informativeText = text
        alert.runModal()
    }
}

/// ScoreDlg.dfm "The contest is over": 394 × 102, or 165 tall with the
/// two-layer "Congratulations on a new record!" banner above (the form
/// grows from 129 to 192 and its bottom-anchored controls move down).
@MainActor
final class ScoreDialog: NSObject {
    private let window: NSWindow
    var onHiScorePage: (() -> Void)?

    init(scoreString: String, newRecord: Bool) {
        let extra: CGFloat = newRecord ? 63 : 0
        let size = NSSize(width: 394, height: 102 + extra)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init()
        window.title = "The contest is over"
        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        window.contentView = root

        if newRecord {
            for (x, y, color) in [(29.0, 28.0, Theme.clAqua), (28.0, 26.0, Theme.clGreen)] {
                let l = makeLabel("Congratulations on a new record!",
                                  NSRect(x: x, y: y, width: 340, height: 26), font: Theme.banner)
                l.textColor = color
                root.addSubview(l)
            }
        }
        root.addSubview(makeLabel("Your score string is:",
                                  NSRect(x: 14, y: 8 + extra, width: 200, height: 14)))
        let edit = NSTextField(frame: NSRect(x: 14, y: 28 + extra, width: 365, height: 23))
        edit.stringValue = scoreString
        edit.font = Theme.scoreString
        edit.isEditable = false
        edit.isSelectable = true
        root.addSubview(edit)

        let page = NSButton(title: "Hi-Score web page", target: self, action: #selector(openPage))
        page.frame = NSRect(x: 172, y: 64 + extra, width: 113, height: 25)
        page.keyEquivalent = "\r"  // Default = True
        page.font = Theme.base
        root.addSubview(page)
        let close = NSButton(title: "Close", target: self, action: #selector(closeDialog))
        close.frame = NSRect(x: 292, y: 64 + extra, width: 75, height: 25)
        close.keyEquivalent = "\u{1b}"  // ModalResult = mrCancel
        close.font = Theme.base
        root.addSubview(close)
    }

    func runModal(centeredOn parent: NSWindow?) {
        if let parent {
            // Position = poMainFormCenter.
            let p = parent.frame
            window.setFrameOrigin(NSPoint(x: p.midX - window.frame.width / 2,
                                          y: p.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        NSApp.runModal(for: window)
        window.orderOut(nil)
    }

    @objc private func openPage() { onHiScorePage?() }

    @objc private func closeDialog() { NSApp.stopModal() }
}
