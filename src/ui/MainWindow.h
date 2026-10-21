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
#include "scoring/QsoLog.h"

#include <QMainWindow>
#include <QString>

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
    // Pascal Main.dfm KeyPreview=True: the form sees every keystroke
    // before the focused control (FormKeyPress / FormKeyDown). We get
    // the same by filtering key presses application-wide for widgets in
    // this window; keys the form doesn't handle pass through untouched.
    bool eventFilter(QObject* watched, QEvent* event) override;

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
    // Pascal FStopPressed (Run button / Stop menu while running).
    void stopRequested();
    // Sim::Message as int, plus the Call box text (used for HisCall).
    void sendMessageRequested(int sigMessageEnum, const QString& callField);
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
    // Pascal Edit1Change: the Call box changed; the sim tries to apply
    // it to a call being keyed (UpdateCallInMessage).
    void playerCallEdited(const QString& callField);
    // Pascal Log.SaveQso's effect on the simulation (DX lookup, NR+1).
    void qsoLogged(const QString& call);
    // Esc — Pascal FormKeyPress #27 → Tst.Me.AbortSend.
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
    // Pascal Ini.CompDuration: WPX / HST run length in minutes.
    void setCompetitionDuration(int minutes) { competitionDuration_ = minutes; }
    // AppController.start() reads this on restart to re-apply the
    // persisted Audio Recording Enabled state.
    [[nodiscard]] QAction* audioRecordingAction() const noexcept;

public slots:
    // Sim → GUI (queued from the sim thread).
    void onClockTicked(double seconds);
    void onContestEnded(int mode, bool stoppedByUser);
    // A finished DX station matched the last logged QSO (DataToLastQso).
    void onDxQsoCompleted(const QString& call, int rst, int nr, float minute);
    // Pascal MainForm.Advance, called when a piece of our message ends.
    void onPlayerPieceFinished();
    void onCallEditResult(const QString& callField, bool applied);
    void onSendAborted(bool hadHisCall, bool hadNr);

private:
    void setRunning(int mode);  // Sim::RunMode as int; Stop = idle

    // ── Main.pas operating logic ──────────────────────────────────────
    void sendMsg(int message);          // TMainForm.SendMsg
    void processSpace();                // TMainForm.ProcessSpace
    void processEnter(bool forceSave);  // TMainForm.ProcessEnter
    void wipeBoxes();                   // TMainForm.WipeBoxes
    void saveQso();                     // Log.SaveQso (GUI side)
    void incSpeed();                    // TMainForm.IncSpeed
    void decSpeed();                    // TMainForm.DecSpeed
    void stepBandwidth(int delta);      // SetBw(ComboBox2.ItemIndex ± 1)
    void incRit(int step);              // TMainForm.IncRit (-1, 0, +1)
    void selectCallQuestionMark();      // TMainForm.Edit1Enter
    // Rewrites the log's last row and the score table from log_.
    void showLastQso(bool replaceRow);
    void refreshStats();
    void refreshRateAndHistogram();
    [[nodiscard]] bool hstMode() const noexcept;

    // Pascal Log.pas globals CallSent / NrSent and Main.pas MustAdvance.
    bool callSent_ = false;
    bool nrSent_ = false;
    bool mustAdvance_ = false;
    // UpdateCallInMessage answers arrive asynchronously; answers for
    // edits made before a HisCall send are stale and skipped.
    int pendingCallEditResults_ = 0;
    int ignoredCallEditResults_ = 0;
    // Pascal Ini.CompDuration (INI-only, 1..60, default 60).
    int competitionDuration_ = 60;

    mr::scoring::QsoLog log_;
    double elapsedSeconds_ = 0.0;
    // Pascal Ini.RunMode (Sim::RunMode as int). Stop = 0.
    int runMode_ = 0;
    // Mode of the last run; the log header and score layout follow it
    // after Stop.
    int lastRunMode_ = 1;

    // Path to the per-user score history file. Pascal stores beside
    // the executable as `MorseRunner.lst`; on macOS we use
    // `~/Library/Application Support/MorseRunner/scores.lst`.
    [[nodiscard]] QString scoreHistoryPath() const;
    // Pascal PopupScoreHst writes HstResults.txt beside the .exe; on
    // macOS it goes next to scores.lst in Application Support.
    [[nodiscard]] QString hstResultsPath() const;
    // Append `line` to `path`, creating the file and directory if absent.
    static void appendLine(const QString& path, const QString& line);
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
