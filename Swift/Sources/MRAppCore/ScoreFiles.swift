// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The files Pascal kept next to MorseRunner.exe (the .lst score list,
// HstResults.txt, the .wav recording), under one base directory —
// ~/Library/Application Support/MorseRunner in the app, a temporary
// directory in tests.

import Foundation

public struct ScoreFiles: Sendable {
    public let baseDir: URL

    public init(baseDir: URL) {
        self.baseDir = baseDir
    }

    /// ChangeFileExt(ParamStr(0), '.lst'): PopupScoreWpx's score list.
    public var scoreList: URL { baseDir.appending(path: "scores.lst") }
    /// PopupScoreHst's results.
    public var hstResults: URL { baseDir.appending(path: "HstResults.txt") }
    /// ChangeFileExt(ParamStr(0), '.wav'): AlWavFile1.
    public var recording: URL { baseDir.appending(path: "MorseRunner.wav") }

    /// TStringList LoadFromFile + Add + SaveToFile: appends `line` as a
    /// line of its own, creating the directory and the file as needed.
    public func append(_ line: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try Data((line + "\n").utf8).write(to: url, options: .atomic)
            return
        }
        let h = try FileHandle(forUpdating: url)
        defer { try? h.close() }
        let end = try h.seekToEnd()
        var text = line + "\n"
        if end > 0 {
            // The list's last line may lack its line break.
            try h.seek(toOffset: end - 1)
            if try h.read(upToCount: 1) != Data("\n".utf8) { text = "\n" + text }
            try h.seekToEnd()
        }
        try h.write(contentsOf: Data(text.utf8))
    }

    /// The score list's text, or nil when it does not exist.
    public func scoreListContents() -> String? {
        guard let data = FileManager.default.contents(atPath: scoreList.path(percentEncoded: false))
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public var recordingExists: Bool {
        FileManager.default.fileExists(atPath: recording.path(percentEncoded: false))
    }
}
