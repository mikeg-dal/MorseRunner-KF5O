// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Main.dfm Panel1 (alBottom, 700x119). Contains the QSO entry
// strip on the left (Call / RST / Nr edits + F1..F8 push buttons),
// the centre status panels (Clock / Mode / Rate / Histogram / RIT),
// and the right-side ScoreTable. Phase D leaves every control
// inert — labels are static, buttons fire a placeholder slot, the
// histogram and score table render empty.

#pragma once

#include <QWidget>

class QFrame;
class QLabel;
class QLineEdit;
class QPushButton;

namespace mr::ui {

class HistogramPanel;
class RitSlider;

class BottomPanel : public QWidget {
    Q_OBJECT
public:
    explicit BottomPanel(QWidget* parent = nullptr);

    // Phase-E hooks.
    [[nodiscard]] QLineEdit* callEdit() const noexcept { return callEdit_; }
    [[nodiscard]] QLineEdit* rstEdit() const noexcept { return rstEdit_; }
    [[nodiscard]] QLineEdit* nrEdit() const noexcept { return nrEdit_; }
    [[nodiscard]] QLabel* clockLabel() const noexcept { return clockLabel_; }
    [[nodiscard]] QLabel* modeLabel() const noexcept { return modeLabel_; }
    [[nodiscard]] QLabel* rateLabel() const noexcept { return rateLabel_; }
    [[nodiscard]] HistogramPanel* histogramPanel() const noexcept {
        return histogramPanel_;
    }
    [[nodiscard]] RitSlider* ritSlider() const noexcept { return ritSlider_; }
    // Score-table cell accessor. row: 0=Pts, 1=Mult, 2=Score.
    // col: 0=Raw, 1=Verified.
    [[nodiscard]] QLabel* scoreCell(int row, int col) const noexcept {
        if (row < 0 || row > 2 || col < 0 || col > 1) {
            return nullptr;
        }
        return scoreCells_[row][col];
    }

    // Pascal Run(): in HST the ListView is hidden and Panel11's own
    // caption (bold 19 px) shows the score; any other run shows the
    // table again. Stop leaves whichever is showing.
    void setScoreTableVisible(bool visible);
    // Pascal UpdateStatsHst: Panel11.Caption := Score.
    void setHstScore(int score);

    // F1..F8 buttons (index 0..7). Phase E connects each to
    // SimulationWorker::sendPlayerMessage. Read-only — buttons live
    // for the panel's lifetime.
    [[nodiscard]] QPushButton* fKeyButton(int index) const noexcept {
        return (index >= 0 && index < 8) ? fKeyButtons_[index] : nullptr;
    }

private:
    void buildEntryFields(QWidget* host);
    void buildFunctionKeys(QWidget* host);
    void buildClockPanel(QWidget* host);
    void buildModePanel(QWidget* host);
    void buildRatePanel(QWidget* host);
    void buildHistogramPanel(QWidget* host);
    void buildRitSliderPanel(QWidget* host);
    void buildScoreTable(QWidget* host);

    QLineEdit* callEdit_ = nullptr;
    QLineEdit* rstEdit_ = nullptr;
    QLineEdit* nrEdit_ = nullptr;
    QLabel* clockLabel_ = nullptr;
    QLabel* modeLabel_ = nullptr;
    QLabel* rateLabel_ = nullptr;
    HistogramPanel* histogramPanel_ = nullptr;
    RitSlider* ritSlider_ = nullptr;
    QPushButton* fKeyButtons_[8] = {};
    // [row][col] = score-table cell. Live-updated in MainWindow.
    QLabel* scoreCells_[3][2] = {};
    QWidget* scoreGrid_ = nullptr;     // ListView1
    QLabel* hstScoreLabel_ = nullptr;  // Panel11.Caption
};

}  // namespace mr::ui
