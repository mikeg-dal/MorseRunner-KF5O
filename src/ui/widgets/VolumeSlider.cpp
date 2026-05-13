// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/widgets/VolumeSlider.h"

#include "core/Constants.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPalette>

#include <algorithm>

namespace mr::ui {

namespace {

// Pascal Main.dfm: VolumeSlider1.Value = 0.75 (default), Margin = 5,
// DbScale = 60. The default normalised value of 0.75 reads as −15 dB.
constexpr double kDefaultValue = 0.75;
constexpr int kMargin = 5;
constexpr double kDbScale = 60.0;  // ± per side of the centre

}  // namespace

VolumeSlider::VolumeSlider(QWidget* parent) : QWidget(parent) {
    setAutoFillBackground(true);
    setCursor(Qt::SizeHorCursor);
    setToolTip(QStringLiteral("Monitor level (double-click to reset)"));
}

void VolumeSlider::setValue(double v) {
    const double clamped = std::clamp(v, 0.0, 1.0);
    if (clamped == value_) {
        return;
    }
    value_ = clamped;
    update();
    emit valueChanged(value_);
}

double VolumeSlider::db() const noexcept {
    // Pascal: Db := DbScale * 2 * (Value - 0.75). Centred at the
    // default value so a 0.75 reading is 0 dB inside the formula; the
    // labelled −15 dB in the UI comes from a baked-in −15 dB
    // attenuation chain in the AGC.
    return kDbScale * 2.0 * (static_cast<double>(value_) - kDefaultValue);
}

void VolumeSlider::setDb(double db) {
    setValue(kDefaultValue + (db / (kDbScale * 2.0)));
}

void VolumeSlider::paintEvent(QPaintEvent* /*event*/) {
    QPainter p(this);
    const int w = width();
    const int h = height();

    // Channel: thin recessed horizontal bar in the middle.
    p.fillRect(rect(), palette().color(QPalette::Button));
    const int channelY = h / 2 - 1;
    p.setPen(palette().color(QPalette::Dark));
    p.drawLine(kMargin, channelY, w - kMargin, channelY);
    p.setPen(palette().color(QPalette::Light));
    p.drawLine(kMargin, channelY + 1, w - kMargin, channelY + 1);

    // Knob.
    const int knobX = kMargin
        + static_cast<int>(value_ * (w - 2 * kMargin));
    constexpr int kKnobWidth = 8;
    const int knobLeft = std::clamp(knobX - kKnobWidth / 2, 0, w - kKnobWidth);
    p.setBrush(palette().color(QPalette::Button));
    p.setPen(palette().color(QPalette::Shadow));
    p.drawRoundedRect(knobLeft, 2, kKnobWidth, h - 4, 2, 2);
}

void VolumeSlider::setValueFromX(int x) {
    const int w = width();
    if (w <= 2 * kMargin) {
        return;
    }
    const double t = static_cast<double>(x - kMargin)
                     / static_cast<double>(w - 2 * kMargin);
    setValue(t);
}

void VolumeSlider::mousePressEvent(QMouseEvent* event) {
    setValueFromX(static_cast<int>(event->position().x()));
}

void VolumeSlider::mouseMoveEvent(QMouseEvent* event) {
    if ((event->buttons() & Qt::LeftButton) != 0) {
        setValueFromX(static_cast<int>(event->position().x()));
    }
}

void VolumeSlider::mouseDoubleClickEvent(QMouseEvent* /*event*/) {
    // Pascal VolmSldr.OnDblClick → reset to the default. Saves the
    // user from hunting for "0 dB" when they've drifted.
    setValue(kDefaultValue);
}

}  // namespace mr::ui
