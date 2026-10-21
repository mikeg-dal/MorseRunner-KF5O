// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Colours and fonts from the shipped v1.68 form (Main.dfm). Delphi
// TColor literals are $00BBGGRR; Font.Height is in pixels, which is one
// point on macOS. MS Sans Serif becomes the system font (platform delta);
// Arial and Courier New exist on macOS and are used as-is.

import AppKit
import MRAppCore

@MainActor
enum Theme {
    /// Delphi TColor ($00BBGGRR) → sRGB.
    static func delphi(_ bgr: UInt32) -> NSColor {
        let c = DelphiColor.rgb(bgr)
        return NSColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255,
                       blue: CGFloat(c.blue) / 255, alpha: 1)
    }

    static let logBackground = delphi(16_711_401)   // Shape1 #E9FEFE
    static let ritIndicator = delphi(12_902_431)    // Shape2 #1FE0C4
    static let clockText = delphi(14_151_712)       // Panel2 font #20F0D7
    static let logoShadow = delphi(12_369_084)      // Label14 #BCBCBC
    static let clGreen = NSColor(srgbRed: 0, green: 0x80 / 255.0, blue: 0, alpha: 1)
    static let clRed = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    static let clBlue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    static let clAqua = NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)
    static let clInfoBk = NSColor(srgbRed: 1, green: 1, blue: 0xE1 / 255.0, alpha: 1)
    static let bevelShadow = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)  // clBtnShadow
    static let bevelHighlight = NSColor.white                                         // clBtnHighlight
    static let btnFace = NSColor(srgbRed: 0xF0 / 255.0, green: 0xF0 / 255.0, blue: 0xF0 / 255.0, alpha: 1)  // clBtnFace
    static let wedgeFill = NSColor(srgbRed: 0xD4 / 255.0, green: 0xD0 / 255.0, blue: 0xC8 / 255.0, alpha: 1)  // classic clBtnFace
    static let darkShadow = NSColor(srgbRed: 0x69 / 255.0, green: 0x69 / 255.0, blue: 0x69 / 255.0, alpha: 1)  // cl3DDkShadow

    /// Panel4's colour token.
    static func color(_ c: ModeColor) -> NSColor {
        switch c {
        case .red: clRed
        case .green: clGreen
        }
    }

    /// MainForm: MS Sans Serif, Height -11.
    static let base = NSFont.systemFont(ofSize: 11)
    static let baseBold = NSFont.boldSystemFont(ofSize: 11)
    /// Edit1..3: Height -16, bold.
    static let entry = NSFont.boldSystemFont(ofSize: 16)
    /// Panel2: Arial, Height -24.
    static let clock = NSFont(name: "Arial", size: 24) ?? .systemFont(ofSize: 24)
    /// Panel11 caption in HST: Height -19, bold.
    static let hstScore = NSFont.boldSystemFont(ofSize: 19)
    /// RichEdit1: Courier New, Height -13.
    static let log = NSFont(name: "Courier New", size: 13)
        ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
    /// Label12..14 logo: Arial, Height -35, bold italic.
    static let logo = NSFont(name: "Arial Bold Italic", size: 35) ?? .boldSystemFont(ofSize: 35)
    /// ScoreDialog banner: Arial, Height -21, bold.
    static let banner = NSFont(name: "Arial Bold", size: 21) ?? .boldSystemFont(ofSize: 21)
    /// ScoreDialog Edit1: Courier New, Height -12.
    static let scoreString = NSFont(name: "Courier New", size: 12)
        ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
}
