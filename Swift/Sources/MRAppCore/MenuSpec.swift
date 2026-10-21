// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MainMenu1 / PopupMenu1 / SpeedButton4..11 as data (Main.dfm).
//
// F8 is on both Run › Pile-Up and Send › NIL in the shipped v1.68 form.
// The port gives it to Pile-Up while stopped (when NIL has nothing to
// answer) and to NIL while a run is on (when Pile-Up is disabled):
// shortcutOwner(_:running:). HST Competition is Ctrl-F8.

import Foundation
import MRSimulation

public struct MenuShortcut: Sendable, Hashable {
    /// A FunctionKey code point.
    public let key: UInt32
    public let control: Bool

    public init(key: UInt32, control: Bool = false) {
        self.key = key
        self.control = control
    }
}

public struct SendItem: Sendable, Equatable {
    public let title: String
    public let message: Message
    /// F1…F8.
    public let functionKey: Int
    /// SpeedButton caption.
    public let buttonCaption: String

    public var shortcut: MenuShortcut { MenuShortcut(key: FunctionKey.f(functionKey)) }
}

public struct RunItem: Sendable, Equatable {
    public let title: String
    public let mode: RunMode
    public let shortcut: MenuShortcut?
}

public struct LevelItem: Sendable, Equatable {
    public let title: String
    /// SelfMonClick's Tag (dB).
    public let tag: Int
}

public enum MenuSpec {
    /// Send menu (SendClick, Tag = message) and the F-key buttons.
    public static let sendItems: [SendItem] = [
        SendItem(title: "CQ", message: .cq, functionKey: 1, buttonCaption: "F1  CQ"),
        SendItem(title: "Number", message: .nr, functionKey: 2, buttonCaption: "F2  <#>"),
        SendItem(title: "TU", message: .tu, functionKey: 3, buttonCaption: "F3  TU"),
        SendItem(title: "My Call", message: .myCall, functionKey: 4, buttonCaption: "F4  <my>"),
        SendItem(title: "His Call", message: .hisCall, functionKey: 5, buttonCaption: "F5  <his>"),
        SendItem(title: "QSO B4", message: .b4, functionKey: 6, buttonCaption: "F6  B4"),
        SendItem(title: "<?>", message: .qm, functionKey: 7, buttonCaption: "F7  ?"),
        SendItem(title: "NIL", message: .nilMsg, functionKey: 8, buttonCaption: "F8  NIL"),
    ]

    /// Run menu (RunMNUClick, Tag = mode). PopupMenu1 has the same items
    /// without shortcuts, Pile-Up as its default (bold) item.
    public static let runItems: [RunItem] = [
        RunItem(title: "Pile-Up", mode: .pileUp, shortcut: MenuShortcut(key: FunctionKey.f8)),
        RunItem(title: "Single Calls", mode: .single, shortcut: nil),
        RunItem(title: "WPX Competition", mode: .wpx, shortcut: nil),
        RunItem(title: "HST Competition", mode: .hst,
                shortcut: MenuShortcut(key: FunctionKey.f8, control: true)),
    ]

    /// Settings › CW Speed: 10…60 WPM step 5 (NWPMClick, Tag = WPM).
    public static let speeds: [Int] = Array(stride(from: 10, through: 60, by: 5))
    /// Settings › Mon. Level (SelfMonClick, Tag = dB).
    public static let monitorLevels: [LevelItem] = [-60, -40, -20, 0, 20].map {
        LevelItem(title: $0 > 0 ? "+\($0) dB" : "\($0) dB", tag: $0)
    }
    /// Settings › Activity: 1…9.
    public static let activities: [Int] = Array(1...9)
    /// Settings › Duration (Duration1Click, Tag = minutes).
    public static let durations: [Int] = [5, 10, 15, 30, 60, 90, 120]
    /// Settings › QRN, QRM, QSB, Flutter, LIDS (LIDS1Click).
    public static let conditions = ["QRN", "QRM", "QSB", "Flutter", "LIDS"]

    public static let hiScoreURL = "https://www.dxatlas.com/MorseRunner/MrScore.asp"
    public static let webPageURL = "https://www.dxatlas.com/MorseRunner"

    /// Every item that carries `shortcut`.
    public static func items(with shortcut: MenuShortcut) -> [String] {
        runItems.filter { $0.shortcut == shortcut }.map { "Run/\($0.title)" }
            + sendItems.filter { $0.shortcut == shortcut }.map { "Send/\($0.title)" }
    }

    /// Which item a shortcut reaches: run items while stopped (they are
    /// disabled during a run), send items otherwise.
    public static func shortcutOwner(_ shortcut: MenuShortcut, running: Bool) -> String? {
        if !running, let r = runItems.first(where: { $0.shortcut == shortcut }) {
            return "Run/\(r.title)"
        }
        if let s = sendItems.first(where: { $0.shortcut == shortcut }) { return "Send/\(s.title)" }
        return nil
    }

    /// Whether Run › `item` should carry its shortcut right now.
    public static func runShortcutActive(_ item: RunItem, running: Bool) -> Bool {
        guard let sc = item.shortcut else { return false }
        return shortcutOwner(sc, running: running) == "Run/\(item.title)"
    }
}

/// Delphi TColor literals are $00BBGGRR.
public enum DelphiColor {
    /// (red, green, blue), each 0…255.
    public static func rgb(_ bgr: UInt32) -> (red: Int, green: Int, blue: Int) {
        (Int(bgr & 0xFF), Int((bgr >> 8) & 0xFF), Int((bgr >> 16) & 0xFF))
    }
}
