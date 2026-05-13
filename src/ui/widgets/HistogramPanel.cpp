// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/widgets/HistogramPanel.h"

#include "core/Constants.h"

#include <QColor>
#include <QPainter>
#include <QPalette>

namespace mr::ui {

namespace {

// Pascal Log.pas constants: clInfoBk background (≈ #FFFFE1) and
// clGreen bars. Bars are 3 px wide on a 4 px stride; baseline sits
// 3 px above the bottom of the widget; each QSO adds 2 px of height.
constexpr QColor kHistogramBg{0xFF, 0xFF, 0xE1};
constexpr QColor kHistogramBar{0x00, 0x80, 0x00};

}  // namespace

HistogramPanel::HistogramPanel(QWidget* parent) : QWidget(parent) {
    setAutoFillBackground(true);
    QPalette p = palette();
    p.setColor(QPalette::Window, kHistogramBg);
    setPalette(p);
}

void HistogramPanel::setBinCount(int binIndex, int count) {
    if (binIndex < 0 || binIndex >= static_cast<int>(bins_.size())) {
        return;
    }
    bins_[static_cast<std::size_t>(binIndex)] = count;
    update();
}

void HistogramPanel::setAllBins(
    const std::array<int, mr::constants::Ui::kHistogramBins>& counts) {
    bins_ = counts;
    update();
}

void HistogramPanel::clear() {
    bins_.fill(0);
    update();
}

void HistogramPanel::paintEvent(QPaintEvent* /*event*/) {
    using namespace mr::constants::Ui;

    QPainter p(this);
    p.fillRect(rect(), kHistogramBg);
    p.setPen(Qt::NoPen);
    p.setBrush(kHistogramBar);

    const int h = height();
    for (std::size_t i = 0; i < bins_.size(); ++i) {
        const int count = bins_[i];
        if (count <= 0) {
            continue;
        }
        // Pascal: x = i*4 + 1, width = 3.
        const int x = static_cast<int>(i) * kHistogramStridePx + 1;
        // Pascal: y = Height - 3 - count*2, height = bottom - y.
        const int bottom = h - kHistogramBaselinePx;
        const int barH = count * kHistogramBarUnitPx;
        const int y = bottom - barH;
        p.drawRect(x, y, kHistogramBarWidthPx, barH);
    }
}

}  // namespace mr::ui
