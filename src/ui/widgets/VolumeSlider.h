// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/VolmSldr.pas (TVolumeSlider). Horizontal volume slider
// with a non-linear dB-mapped scale. The underlying state is a
// normalized value in [0, 1]; the visual knob position uses a square
// mapping (Pascal Pos = Value * Width) but the dB readout is computed
// via Db = DbScale * 2 * (Value - kDefaultZero) where kDefaultZero
// corresponds to "−15 dB" at value 0.75.
//
// Phase D leaves the value inert; double-click reset to default is
// wired so the user can quickly inspect the behaviour.

#pragma once

#include <QWidget>

namespace mr::ui {

class VolumeSlider : public QWidget {
    Q_OBJECT
public:
    explicit VolumeSlider(QWidget* parent = nullptr);

    void setValue(double v);   // normalised 0..1
    [[nodiscard]] double value() const noexcept { return value_; }

    // Convenience: read/write the user-visible dB equivalent.
    [[nodiscard]] double db() const noexcept;
    void setDb(double db);

signals:
    void valueChanged(double v);

protected:
    void paintEvent(QPaintEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseDoubleClickEvent(QMouseEvent* event) override;

private:
    void setValueFromX(int x);

    double value_ = 0.75;  // matches Pascal default (≡ −15 dB)
};

}  // namespace mr::ui
