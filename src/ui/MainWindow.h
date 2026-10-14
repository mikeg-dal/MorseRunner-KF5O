// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Hand-coded top-level window matching Main.dfm pixel-for-pixel.
// Phase E exposes signals so AppController can wire them to
// SimulationWorker's GUI-facing slots via Qt::QueuedConnection.

#pragma once

#include "core/Constants.h"

#include <QHash>
#include <QMainWindow>
#include <QSet>
#include <QString>

#include <array>
#include <memory>

class QMenu;
class QAction;
class QPushButton;

namespace mr::ui {

class BottomPanel;
class RightPanel;
class LogView;
class HistogramPanel;
class RitSlider;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);
    ~MainWindow() override;

    // Phase-E hooks. AppController reads these to wire signals.
    [[nodiscard]] RightPanel* rightPanel() const noexcept { return rightPanel_; }
    [[nodiscard]] BottomPanel* bottomPanel() const noexcept { return bottomPanel_; }
    [[nodiscard]] LogView* logView() const noexcept { return logView_; }

protected:
    // Pascal Main.dfm KeyPreview=True hands every keystroke to the form
    // before its focused control. We do the same by overriding the
    // protected QWidget keyPressEvent — when a shortcut matches we
    // consume it; otherwise we forward to the base so the QLineEdits
    // still receive normal typing.
    void keyPressEvent(QKeyEvent* event) override;

public:

    // Run + Send + Settings actions used by AppController to connect
    // to SimulationWorker slots.
    [[nodiscard]] QAction* runPileUpAction() const noexcept;
    [[nodiscard]] QAction* runSingleAction() const noexcept;
    [[nodiscard]] QAction* runWpxAction() const noexcept;
    [[nodiscard]] QAction* runHstAction() const noexcept;
    [[nodiscard]] QAction* runStopAction() const noexcept;
    [[nodiscard]] QAction* sendAction(int fKeyIndex) const noexcept;  // 0..7

    [[nodiscard]] QAction* qrnAction() const noexcept;
    [[nodiscard]] QAction* qrmAction() const noexcept;
    [[nodiscard]] QAction* qsbAction() const noexcept;
    [[nodiscard]] QAction* flutterAction() const noexcept;
    [[nodiscard]] QAction* lidsAction() const noexcept;
    [[nodiscard]] QAction* qskAction() const noexcept;

    // The F1..F8 push buttons in BottomPanel — emit clicked() when
    // the user presses them with the mouse. The Send menu emits via
    // the QAction shortcut.
    [[nodiscard]] QPushButton* fKeyButton(int fKeyIndex) const noexcept;

signals:
    // Convenience signals that fan in clicks from BOTH the menu and
    // the matching right-panel checkbox so AppController only has to
    // connect once.
    void runModeRequested(int sigRunModeEnum);
    void sendMessageRequested(int sigMessageEnum);
    void qrnToggled(bool on);
    void qrmToggled(bool on);
    void qsbToggled(bool on);
    void flutterToggled(bool on);
    void lidsToggled(bool on);
    void qskToggled(bool on);

    // E.G2: numeric settings + MyCall. Fanned in from both the
    // right-panel control and the matching Settings menu submenu.
    void wpmChanged(int wpm);
    void pitchChanged(int hz);
    void bandwidthChanged(int hz);
    void activityChanged(int activity);
    void durationChanged(int minutes);
    void monitorLevelChanged(double normalisedValue);
    void myCallsignChanged(const QString& call);
    void ritChanged(int hz);
    // Heard-call (the bottom-panel "Call" QLineEdit, Pascal Edit1).
    // The user types the call they hear on the air; F5 then keys it.
    void heardCallsignChanged(const QString& call);
    // E.G4 Esc — aborts the player's current transmission. Pascal's
    // FormKeyDown calls Tst.Me.AbortSend.
    void abortSendRequested();
    // Pascal File → Audio Recording Enabled. `path` is the resolved
    // destination — MainWindow derives it on the GUI thread to avoid
    // a sim-thread QStandardPaths call.
    void audioRecordingToggled(bool on, const QString& path);

public:
    // Pascal Operator1Click: set window title from the persisted
    // operator name. AppController calls this on startup with the
    // loaded value; the HST Operator… menu calls it after a new entry.
    void applyHamNameToTitle(const QString& name);
    // AppController.start() reads this on restart to re-apply the
    // persisted Audio Recording Enabled state.
    [[nodiscard]] QAction* audioRecordingAction() const noexcept;

public slots:
    // Sim → GUI live updates (Phase E.G3). The emitter
    // (SimulationWorker) lives on the sim thread; Qt delivers via
    // QueuedConnection across the boundary.
    void onClockTicked(int seconds);
    void onContestEnded(int mode);
    // E.G4 entry-field: Enter on Call/RST/Nr commits the current
    // QSO to the log pane, clears the fields, and refocuses Call.
    void onSaveQsoRequested();
    // Sim-thread reports a DX station reached Done state. Stored here
    // for Chk-column validation when the user presses Enter.
    void onDxQsoCompleted(const QString& call, int rst, int nr, float minute);

private:
    void setRunning(int mode);  // Sim::RunMode as int; Stop = idle
    // E.G3 live readouts driven from the GUI thread. We don't have a
    // CompletedQso callback yet, so the rate / histogram update on
    // Enter-logged QSOs only — close enough until Phase F's scoring
    // engine takes over.
    int sessionSeconds_ = 0;
    int totalLoggedQsos_ = 0;
    int verifiedQsos_ = 0;
    int scoreRaw_ = 0;
    int scoreVerified_ = 0;
    // Most recent run mode the user selected. Tracked so
    // onSaveQsoRequested can pick HST-style vs WPX-style scoring
    // without a sim round-trip. Default is the user's last choice
    // before Stop; resets to PileUp on cold start.
    int currentRunMode_ = 1;  // RunMode::PileUp — sentinel only
    // Logged-prefix tracker for the WPX multiplier column. A given
    // prefix counts once regardless of how many QSOs we have with it.
    QSet<QString> rawPrefixes_;
    QSet<QString> verifiedPrefixes_;
    // Calls already in the log this session; used for DUP detection
    // in the Chk column.
    QSet<QString> loggedCalls_;
    // Truth back-fill from the sim. Key = uppercased call.
    struct DxTruth { int rst; int nr; };
    QHash<QString, DxTruth> truthByCall_;
    // Mirror of HistogramPanel's bins so onSaveQsoRequested can do a
    // read-bump-write without exposing internal state on the panel.
    std::array<int, mr::constants::Ui::kHistogramBins> histogramBins_{};

    // Path to the per-user score history file. Pascal stores beside
    // the executable as `MorseRunner.lst`; on macOS we use
    // `~/Library/Application Support/MorseRunner/scores.lst`.
    [[nodiscard]] QString scoreHistoryPath() const;
    // Append `line` to the score history file, creating it (and the
    // containing directory) if absent.
    void appendScoreHistoryLine(const QString& line) const;
    // Path to the recorded WAV — Pascal saves it next to the .exe;
    // on macOS we use ~/Library/Application Support/MorseRunner/.
    [[nodiscard]] QString recordedAudioPath() const;

    void buildMenus();
    void buildFileMenu();
    void buildRunMenu();
    void buildSendMenu();
    void buildSettingsMenu();
    void buildHelpMenu();
    void buildCentralLayout();
    void wireMenuFanouts();
    void wireBottomPanelClicks();
    void wireCheckBoxSync();
    void wireNumericSettings();

    // Phase-D placeholder slot — non-wired menu actions still land
    // here so we can log what was clicked.
    Q_SLOT void onPlaceholderAction();

    struct Menus;
    std::unique_ptr<Menus> menus_;
    BottomPanel* bottomPanel_ = nullptr;
    RightPanel* rightPanel_ = nullptr;
    LogView* logView_ = nullptr;
    QPushButton* fKeyButtons_[8] = {};
};

}  // namespace mr::ui
