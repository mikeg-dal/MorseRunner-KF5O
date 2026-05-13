// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Main.dfm Panel8 + Shape2 — a thin horizontal bar with an
// orange indicator whose width tracks the RX bandwidth and whose
// horizontal centre tracks the RIT offset. Clicking left/right of the
// indicator shifts the RIT by ±50 Hz; clicking on the indicator zeros
// the RIT.
//
// Phase D leaves the click handling inert; Phase E wires the RIT
// changes to Sim::Contest::settings_.ritHz.

#pragma once

#include <QWidget>

namespace mr::ui {

class RitSlider : public QWidget {
    Q_OBJECT
public:
    explicit RitSlider(QWidget* parent = nullptr);

    void setRitHz(int hz);
    void setBandwidthHz(int hz);

    [[nodiscard]] int ritHz() const noexcept { return ritHz_; }
    [[nodiscard]] int bandwidthHz() const noexcept { return bandwidthHz_; }

signals:
    void ritChanged(int hz);

protected:
    void paintEvent(QPaintEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;

private:
    [[nodiscard]] int indicatorWidth() const noexcept;
    [[nodiscard]] int indicatorLeft() const noexcept;
    // Inverse of indicatorLeft — given a cursor x within the widget,
    // return the RIT offset (Hz) that would place the indicator under
    // the cursor. Snaps to the kRitStepHz grid.
    [[nodiscard]] int ritForCursorX(int x) const noexcept;

    int ritHz_ = 0;
    int bandwidthHz_ = 500;
    bool dragging_ = false;
};

}  // namespace mr::ui
