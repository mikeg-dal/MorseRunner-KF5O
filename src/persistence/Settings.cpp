// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "persistence/Settings.h"

#include <algorithm>

#include <QCoreApplication>

namespace mr::persistence {

namespace {

// Group/key constants. Layout matches Pascal Ini.pas sections.
constexpr auto kStationGrp  = "Station/";
constexpr auto kBandGrp     = "Band/";
constexpr auto kContestGrp  = "Contest/";

constexpr auto kKeyCall      = "Station/Call";
constexpr auto kKeyWpm       = "Station/Wpm";
constexpr auto kKeyPitch     = "Station/Pitch";
constexpr auto kKeyBandwidth = "Station/BandWidth";
constexpr auto kKeyQsk       = "Station/Qsk";
constexpr auto kKeyMonitor   = "Station/SelfMonVolume";

constexpr auto kKeyActivity = "Band/Activity";
constexpr auto kKeyQrn      = "Band/Qrn";
constexpr auto kKeyQrm      = "Band/Qrm";
constexpr auto kKeyQsb      = "Band/Qsb";
constexpr auto kKeyFlutter  = "Band/Flutter";
constexpr auto kKeyLids     = "Band/Lids";

constexpr auto kKeyDuration = "Contest/Duration";
constexpr auto kKeyHiScore  = "Contest/HiScore";
constexpr auto kKeyHamName  = "Station/Name";
constexpr auto kKeySaveWav  = "Station/SaveWav";
constexpr auto kKeyCompDuration   = "Contest/CompetitionDuration";
constexpr auto kKeyCallsFromKeyer = "Station/CallsFromKeyer";

}  // namespace

Settings::Settings()
    : store_(std::make_unique<QSettings>(
          QSettings::NativeFormat, QSettings::UserScope,
          QStringLiteral("garciamike1"),
          QStringLiteral("MorseRunner"))) {}

UserSettings Settings::load() const {
    UserSettings s;
    s.myCallsign       = store_->value(kKeyCall,      s.myCallsign).toString();
    s.wpm              = store_->value(kKeyWpm,       s.wpm).toInt();
    s.pitchHz          = store_->value(kKeyPitch,     s.pitchHz).toInt();
    s.bandwidthHz      = store_->value(kKeyBandwidth, s.bandwidthHz).toInt();
    s.activity         = store_->value(kKeyActivity,  s.activity).toInt();
    s.durationMinutes  = store_->value(kKeyDuration,  s.durationMinutes).toInt();
    s.monitorLevel     = store_->value(kKeyMonitor,   s.monitorLevel).toDouble();
    s.qsk              = store_->value(kKeyQsk,       s.qsk).toBool();
    s.qrn              = store_->value(kKeyQrn,       s.qrn).toBool();
    s.qrm              = store_->value(kKeyQrm,       s.qrm).toBool();
    s.qsb              = store_->value(kKeyQsb,       s.qsb).toBool();
    s.flutter          = store_->value(kKeyFlutter,   s.flutter).toBool();
    s.lids             = store_->value(kKeyLids,      s.lids).toBool();
    s.hiScore          = store_->value(kKeyHiScore,   s.hiScore).toInt();
    s.hamName          = store_->value(kKeyHamName,   s.hamName).toString();
    s.saveWav          = store_->value(kKeySaveWav,   s.saveWav).toBool();
    // Pascal: Wpm := Max(10, Min(120, Wpm)); CompDuration clamped 1..60.
    s.wpm = std::clamp(s.wpm, 10, 120);
    s.competitionDuration = std::clamp(
        store_->value(kKeyCompDuration, s.competitionDuration).toInt(), 1, 60);
    s.callsFromKeyer = store_->value(kKeyCallsFromKeyer, s.callsFromKeyer).toBool();
    return s;
}

void Settings::setMyCallsign(const QString& v) { store_->setValue(kKeyCall, v);      store_->sync(); }
void Settings::setWpm(int v)                   { store_->setValue(kKeyWpm, v);       store_->sync(); }
void Settings::setPitchHz(int v)               { store_->setValue(kKeyPitch, v);     store_->sync(); }
void Settings::setBandwidthHz(int v)           { store_->setValue(kKeyBandwidth, v); store_->sync(); }
void Settings::setActivity(int v)              { store_->setValue(kKeyActivity, v);  store_->sync(); }
void Settings::setDurationMinutes(int v)       { store_->setValue(kKeyDuration, v);  store_->sync(); }
void Settings::setMonitorLevel(double v)       { store_->setValue(kKeyMonitor, v);   store_->sync(); }
void Settings::setQsk(bool v)                  { store_->setValue(kKeyQsk, v);       store_->sync(); }
void Settings::setQrn(bool v)                  { store_->setValue(kKeyQrn, v);       store_->sync(); }
void Settings::setQrm(bool v)                  { store_->setValue(kKeyQrm, v);       store_->sync(); }
void Settings::setQsb(bool v)                  { store_->setValue(kKeyQsb, v);       store_->sync(); }
void Settings::setFlutter(bool v)              { store_->setValue(kKeyFlutter, v);   store_->sync(); }
void Settings::setLids(bool v)                 { store_->setValue(kKeyLids, v);      store_->sync(); }

int Settings::hiScore() const          { return store_->value(kKeyHiScore, 0).toInt(); }
void Settings::setHiScore(int v)       { store_->setValue(kKeyHiScore, v);    store_->sync(); }

QString Settings::hamName() const                  { return store_->value(kKeyHamName).toString(); }
void Settings::setHamName(const QString& v)        { store_->setValue(kKeyHamName, v); store_->sync(); }

bool Settings::saveWav() const                     { return store_->value(kKeySaveWav, false).toBool(); }
void Settings::setSaveWav(bool v)                  { store_->setValue(kKeySaveWav, v); store_->sync(); }

}  // namespace mr::persistence
