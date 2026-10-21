// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// QSettings-backed persistence. macOS NativeFormat writes to
// ~/Library/Preferences/com.garciamike1.morserunner.plist. Schema mirrors
// the Pascal Ini groups (Station / Band / Contest / System) so a future
// .ini migration shim has somewhere to land.

#pragma once

#include <QObject>
#include <QSettings>
#include <QString>

#include <memory>

namespace mr::persistence {

// Snapshot of every persisted control. Default values match the
// Pascal Ini.pas defaults so a fresh install behaves identically to a
// fresh original install.
struct UserSettings {
    // Pascal FromIni defaults when a key is missing (a fresh install
    // ships no .ini): Pitch combo index 3 = 450 Hz, BandWidth index 9 =
    // 550 Hz, Activity 2. These override the form's 600 / 500 / 3.
    QString myCallsign = QStringLiteral("VE3NEA");
    int wpm = 30;
    int pitchHz = 450;
    int bandwidthHz = 550;
    int activity = 2;
    int durationMinutes = 30;
    double monitorLevel = 0.75;   // selfMonGain01

    bool qsk = true;
    bool qrn = true;
    bool qrm = true;
    bool qsb = true;
    bool flutter = true;
    bool lids = true;

    // Pascal Ini.pas SEC_TST/HiScore. The WPX ScoreDialog uses it to
    // decide whether to show the "Congratulations on a new record!"
    // banner.
    int hiScore = 0;
    // Pascal SEC_STN/Name. Set via Settings → HST Operator… and
    // appended to the window title plus written to the HST result
    // logfile.
    QString hamName;
    // Pascal SEC_STN/SaveWav. File → Audio Recording Enabled toggle.
    bool saveWav = false;
    // INI-only keys (no UI in the original either; edit the plist).
    // SEC_TST/CompetitionDuration: WPX / HST run length, clamped 1..60.
    int competitionDuration = 60;
    // SEC_STN/CallsFromKeyer: an external keyer sends the call.
    bool callsFromKeyer = false;
};

class Settings {
public:
    Settings();

    // Loads the latest values from the plist into a `UserSettings`.
    // Missing keys fall back to their hard-coded defaults.
    [[nodiscard]] UserSettings load() const;

    // Atomic per-field writers. All writers call `sync()` so a crash
    // immediately after a control change doesn't lose the value.
    void setMyCallsign(const QString& v);
    void setWpm(int v);
    void setPitchHz(int v);
    void setBandwidthHz(int v);
    void setActivity(int v);
    void setDurationMinutes(int v);
    void setMonitorLevel(double v);

    void setQsk(bool v);
    void setQrn(bool v);
    void setQrm(bool v);
    void setQsb(bool v);
    void setFlutter(bool v);
    void setLids(bool v);

    [[nodiscard]] int hiScore() const;
    void setHiScore(int v);

    [[nodiscard]] QString hamName() const;
    void setHamName(const QString& v);

    [[nodiscard]] bool saveWav() const;
    void setSaveWav(bool v);

private:
    std::unique_ptr<QSettings> store_;
};

}  // namespace mr::persistence
