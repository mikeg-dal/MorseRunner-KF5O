// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit
import MRAppCore
import MRPersistence

/// True when this process is the host of the app-hosted unit tests. The
/// app then creates no window, no audio engine and no sim thread, and
/// never touches the user's defaults or files.
enum TestHost {
    static let isActive: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?
    private var engine: EngineBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !TestHost.isActive else { return }
        let engine = EngineBridge()
        self.engine = engine
        let files = ScoreFiles(baseDir: URL.applicationSupportDirectory.appending(path: "MorseRunner"))
        let c = MainWindowController(engine: engine, settings: Settings.shared(), files: files)
        controller = c
        NSApp.mainMenu = c.mainMenu
        NSApp.windowsMenu = c.windowsMenu
        c.loadSettings()
        engine.start()
        c.showWindow()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !TestHost.isActive }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.teardown()
        engine?.shutdown()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(TestHost.isActive ? .prohibited : .regular)
app.run()
