// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Right-side settings strip — Pascal Main.dfm Panel9 (alRight, 212x284).
// Contains GroupBox1 "Station" (Call, QSK, WPM, Pitch, BW, MonLevel),
// GroupBox3 "Band Conditions" (QRN/QRM/QSB/Flutter/LIDS + Activity),
// and Panel10 at the bottom (Duration spin + Run dropdown button).
//
// Phase D leaves every control inert (no slots connected to logic).
// Phase E wires them to Sim::Contest and the settings layer. The
// public API exposes every named control so Phase E can hook them
// without re-traversing the layout.

#pragma once

#include <QWidget>

class QCheckBox;
class QComboBox;
class QLineEdit;
class QMenu;
class QPushButton;
class QSpinBox;
class QToolButton;

namespace mr::ui {

class VolumeSlider;

class RightPanel : public QWidget {
    Q_OBJECT
public:
    explicit RightPanel(QMenu* runPopupMenu, QWidget* parent = nullptr);

    // Phase-E hooks — each Pascal control surfaces under a name that
    // matches the original .dfm: callEdit ↔ Edit4, qskCheckBox ↔
    // CheckBox1, wpmSpin ↔ SpinEdit1, etc.
    [[nodiscard]] QLineEdit* callEdit() const noexcept { return callEdit_; }
    [[nodiscard]] QCheckBox* qskCheckBox() const noexcept { return qskCheckBox_; }
    [[nodiscard]] QSpinBox* wpmSpin() const noexcept { return wpmSpin_; }
    [[nodiscard]] QComboBox* pitchCombo() const noexcept { return pitchCombo_; }
    [[nodiscard]] QComboBox* bandwidthCombo() const noexcept { return bandwidthCombo_; }
    [[nodiscard]] QCheckBox* qrnCheckBox() const noexcept { return qrnCheckBox_; }
    [[nodiscard]] QCheckBox* qrmCheckBox() const noexcept { return qrmCheckBox_; }
    [[nodiscard]] QCheckBox* qsbCheckBox() const noexcept { return qsbCheckBox_; }
    [[nodiscard]] QCheckBox* flutterCheckBox() const noexcept { return flutterCheckBox_; }
    [[nodiscard]] QCheckBox* lidsCheckBox() const noexcept { return lidsCheckBox_; }
    [[nodiscard]] QSpinBox* activitySpin() const noexcept { return activitySpin_; }
    [[nodiscard]] QSpinBox* durationSpin() const noexcept { return durationSpin_; }
    [[nodiscard]] QToolButton* runButton() const noexcept { return runButton_; }
    [[nodiscard]] VolumeSlider* volumeSlider() const noexcept {
        return reinterpret_cast<VolumeSlider*>(volumeSliderHost_);
    }

private:
    void buildStationGroup(QWidget* host);
    void buildBandConditionsGroup(QWidget* host);
    void buildRunRow(QWidget* host, QMenu* runPopupMenu);

    QLineEdit* callEdit_ = nullptr;
    QCheckBox* qskCheckBox_ = nullptr;
    QSpinBox* wpmSpin_ = nullptr;
    QComboBox* pitchCombo_ = nullptr;
    QComboBox* bandwidthCombo_ = nullptr;
    QWidget* volumeSliderHost_ = nullptr;  // populated in D.G4
    QCheckBox* qrnCheckBox_ = nullptr;
    QCheckBox* qrmCheckBox_ = nullptr;
    QCheckBox* qsbCheckBox_ = nullptr;
    QCheckBox* flutterCheckBox_ = nullptr;
    QCheckBox* lidsCheckBox_ = nullptr;
    QSpinBox* activitySpin_ = nullptr;
    QSpinBox* durationSpin_ = nullptr;
    QToolButton* runButton_ = nullptr;
};

}  // namespace mr::ui
