// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The score list, HstResults.txt and the recording (MRAppCore.ScoreFiles),
// and PopupScoreWpx / PopupScoreHst (MRAppCore.ContestEndPolicy).

import AppKit
import MRAppCore
import MRPersistence
import MRSimulation
import os

extension MainWindowController {
    private static let fileLog = Logger(subsystem: "com.garciamike1.morserunner", category: "files")

    /// ViewScoreTable1Click.
    @objc func viewScoreTable() {
        logView.showPlain(Captions.scoreTableText(fileContents: files.scoreListContents()))
        logView.isHidden = false
        splash.isHidden = true
    }

    /// AudioRecordingEnabled1Click.
    @objc func toggleRecording() {
        saveWav.toggle()
        settings.setSaveWav(saveWav)
    }

    /// PlayRecordedAudio1Click.
    @objc func playRecording() { openURL(files.recording) }

    private func append(_ line: String, to url: URL) {
        do {
            try files.append(line, to: url)
        } catch {
            Self.fileLog.error("could not write \(url.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            showMessage("Could not write \(url.lastPathComponent):\n\(error.localizedDescription)")
        }
    }

    /// The end-of-session popups (Contest.pas GetAudio after Run(rmStop)).
    func contestEnded(mode: RunMode, stoppedByUser: Bool) {
        let outcome = ContestEndPolicy.outcome(
            mode: mode, stoppedByUser: stoppedByUser, table: scoreTable.model,
            call: myCallEdit.stringValue, hamName: hamName, hiScore: hiScore,
            now: now(), timeZone: timeZone())
        switch outcome {
        case .none:
            break
        case .hst(let line, let message):
            append(line, to: files.hstResults)
            showMessage(message)
        case .wpx(let line, _, let newRecord, let newHiScore):
            append(line, to: files.scoreList)
            hiScore = newHiScore
            settings.setHiScore(newHiScore)
            showScoreDialog(line, newRecord)
        }
    }
}
