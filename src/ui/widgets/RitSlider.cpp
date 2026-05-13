// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/widgets/RitSlider.h"

#include "core/Constants.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPalette>

#include <algorithm>

namespace mr::ui {

namespace {

// Pascal Shape2 colour 12902431 → RGB #DFCFC4. The Pascal RIT range
// is documented in Ini.pas; we mirror it via the Ui:: constants.
constexpr QColor kRitIndicatorColor{0xDF, 0xCF, 0xC4};

}  // namespace

RitSlider::RitSlider(QWidget* parent) : QWidget(parent) {
    setAutoFillBackground(true);
    QPalette p = palette();
    p.setColor(QPalette::Window, palette().color(QPalette::Mid));
    setPalette(p);
    setCursor(Qt::PointingHandCursor);
    setToolTip(QStringLiteral("RIT"));
}

void RitSlider::setRitHz(int hz) {
    const int clamped = std::clamp(hz,
                                   mr::constants::Ui::kRitMinHz,
                                   mr::constants::Ui::kRitMaxHz);
    if (clamped == ritHz_) {
        return;
    }
    ritHz_ = clamped;
    update();
    emit ritChanged(ritHz_);
}

void RitSlider::setBandwidthHz(int hz) {
    if (hz == bandwidthHz_ || hz <= 0) {
        return;
    }
    bandwidthHz_ = hz;
    update();
}

int RitSlider::indicatorWidth() const noexcept {
    // Pascal: Width = Ini.Bandwidth / 9. The factor 9 derives from the
    // visible RIT range being ±500 Hz mapped across the panel width:
    // 1000 Hz / 9 ≈ widget-relative scale matching the bandwidth bar.
    return std::max(2, bandwidthHz_ / 9);
}

int RitSlider::indicatorLeft() const noexcept {
    // Pascal: Left = ((PanelWidth - IndicatorWidth) / 2) + (Rit / 9).
    const int centre = (width() - indicatorWidth()) / 2;
    return centre + (ritHz_ / 9);
}

void RitSlider::paintEvent(QPaintEvent* /*event*/) {
    QPainter p(this);
    // Recessed groove (mimic Pascal Panel8 bvLowered look).
    p.fillRect(rect(), palette().color(QPalette::Mid));
    p.setPen(palette().color(QPalette::Dark));
    p.drawLine(0, 0, width() - 1, 0);
    p.setPen(palette().color(QPalette::Light));
    p.drawLine(0, height() - 1, width() - 1, height() - 1);

    // Orange indicator.
    p.setPen(Qt::NoPen);
    p.setBrush(kRitIndicatorColor);
    const int w = indicatorWidth();
    const int l = std::clamp(indicatorLeft(), 0, width() - w);
    p.drawRect(l, 1, w, height() - 2);
}

int RitSlider::ritForCursorX(int x) const noexcept {
    // Inverse of indicatorLeft(). Pascal: Left = ((w - iw)/2) + Rit/9.
    // Solving for Rit gives `9 * (cursorX - iw/2 - centre)`. We snap
    // to kRitStepHz so the readout stays on clean multiples.
    const int w = width();
    const int iw = indicatorWidth();
    const int centre = (w - iw) / 2;
    const int rawRit = (x - iw / 2 - centre) * 9;
    using mr::constants::Ui::kRitStepHz;
    return (rawRit / kRitStepHz) * kRitStepHz;
}

void RitSlider::mousePressEvent(QMouseEvent* event) {
    if (event->button() != Qt::LeftButton) {
        return;
    }
    dragging_ = true;
    setRitHz(ritForCursorX(static_cast<int>(event->position().x())));
}

void RitSlider::mouseMoveEvent(QMouseEvent* event) {
    if (!dragging_) {
        return;
    }
    if ((event->buttons() & Qt::LeftButton) == 0) {
        dragging_ = false;
        return;
    }
    setRitHz(ritForCursorX(static_cast<int>(event->position().x())));
}

void RitSlider::mouseReleaseEvent(QMouseEvent* /*event*/) {
    dragging_ = false;
}

}  // namespace mr::ui
