// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Log.pas::PaintHisto — 48 vertical bars covering 240 minutes
// of contest time in 5-minute bins. clInfoBk (cream) background, clGreen
// bars 3 px wide, 4 px stride, baseline 3 px from the bottom edge.
// Each bar's height is (Histo[i] * 2) pixels where Histo[i] is the
// number of QSOs logged in that 5-minute window.

#pragma once

#include "core/Constants.h"

#include <QWidget>

#include <array>

namespace mr::ui {

class HistogramPanel : public QWidget {
    Q_OBJECT
public:
    explicit HistogramPanel(QWidget* parent = nullptr);

    // Set the count for one bin. The widget auto-repaints. Phase E
    // calls this when a QSO is logged so the histogram updates live.
    void setBinCount(int binIndex, int count);

    // Replace the entire bin array at once.
    void setAllBins(const std::array<int,
                                     mr::constants::Ui::kHistogramBins>& counts);

    void clear();

protected:
    void paintEvent(QPaintEvent* event) override;

private:
    std::array<int, mr::constants::Ui::kHistogramBins> bins_{};
};

}  // namespace mr::ui
