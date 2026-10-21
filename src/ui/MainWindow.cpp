// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/MainWindow.h"

#include "core/Constants.h"
#include "core/Logging.h"
#include "core/Theme.h"
#include "simulation/Engine.h"
#include "simulation/Messages.h"
#include "ui/dialogs/AboutDialog.h"
#include "ui/panels/BottomPanel.h"
#include "ui/panels/RightPanel.h"
#include "ui/widgets/LogView.h"

#include "ui/widgets/RitSlider.h"
#include "ui/widgets/VolumeSlider.h"

#include <QApplication>
#include <QCheckBox>
#include <QDateTime>
#include <QTimer>
#include <QComboBox>
#include <QLineEdit>
#include <QCoreApplication>
#include <QDate>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMessageBox>
#include <QStandardPaths>
#include <QTime>
#include <QUrl>

#include "persistence/Settings.h"
#include "scoring/CallToScore.h"
#include "scoring/Crc32.h"
#include "scoring/ExtractPrefix.h"
#include "ui/dialogs/ScoreDialog.h"
#include "ui/widgets/HistogramPanel.h"
#include "ui/widgets/RitSlider.h"
#include <QPushButton>
#include <QSpinBox>

#include <QAction>
#include <QActionGroup>
#include <QKeySequence>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QObject>
#include <QStatusBar>
#include <QToolButton>
#include <QVBoxLayout>

#include <cmath>

namespace mr::ui {

namespace {

// Helper: build a "<value>" submenu where each item triggers a single
// shared slot and stores the numeric value via QAction::setData. Phase
// D wires them all to MainWindow::onPlaceholderAction; Phase E
// replaces the slot. Pascal Main.dfm uses the Tag property the same
// way to drive `Sender.Tag` dispatch in the .pas handler.
template <typename Func>
void addNumericChoices(QMenu* menu, const std::initializer_list<int>& values,
                       const QString& unitSuffix, QActionGroup* group,
                       Func slot, QObject* receiver) {
    for (int v : values) {
        QString label = QString::number(v);
        if (!unitSuffix.isEmpty()) {
            label.append(QStringLiteral(" ")).append(unitSuffix);
        }
        auto* act = menu->addAction(label);
        act->setCheckable(true);
        act->setData(v);
        group->addAction(act);
        QObject::connect(act, &QAction::triggered, receiver, slot);
    }
}

// Mirror a panel control's value into its Settings submenu: check the
// item whose data matches, or clear every check when the control holds
// a value the menu does not list (e.g. 23 WPM typed into the spin).
void checkMatchingAction(QMenu* menu, int value) {
    for (QAction* a : menu->actions()) {
        a->setChecked(a->data().toInt() == value);
    }
}

}  // namespace

// Holds every named menu/action so the rest of the file can refer to
// them by name (matching the Pascal symbol names from Main.dfm). Kept
// behind a struct so MainWindow.h stays uncluttered.
struct MainWindow::Menus {
    // File
    QMenu* file = nullptr;
    QAction* viewScoreTable = nullptr;
    QAction* viewHiScoreWebPage = nullptr;
    QAction* audioRecordingEnabled = nullptr;
    QAction* playRecordedAudio = nullptr;
    QAction* exit = nullptr;

    // Run (and PopupMenu1 which mirrors the four run-mode entries)
    QMenu* run = nullptr;
    QAction* runPileUp = nullptr;
    QAction* runSingleCalls = nullptr;
    QAction* runWpx = nullptr;
    QAction* runHst = nullptr;
    QAction* runStop = nullptr;
    QMenu* runPopup = nullptr;

    // Send
    QMenu* send = nullptr;
    QAction* sendCq = nullptr;
    QAction* sendNumber = nullptr;
    QAction* sendTu = nullptr;
    QAction* sendMyCall = nullptr;
    QAction* sendHisCall = nullptr;
    QAction* sendQsoB4 = nullptr;
    QAction* sendQm = nullptr;
    QAction* sendNil = nullptr;

    // Settings
    QMenu* settings = nullptr;
    QAction* settingsCall = nullptr;
    QAction* settingsQsk = nullptr;
    QMenu* cwSpeedMenu = nullptr;
    QMenu* cwPitchMenu = nullptr;
    QMenu* cwBandwidthMenu = nullptr;
    QMenu* monLevelMenu = nullptr;
    QAction* settingsQrn = nullptr;
    QAction* settingsQrm = nullptr;
    QAction* settingsQsb = nullptr;
    QAction* settingsFlutter = nullptr;
    QAction* settingsLids = nullptr;
    QMenu* activityMenu = nullptr;
    QMenu* durationMenu = nullptr;
    QAction* settingsHstOperator = nullptr;

    // Help
    QMenu* help = nullptr;
    QAction* helpWebPage = nullptr;
    QAction* helpReadme = nullptr;
    QAction* helpAbout = nullptr;
};

MainWindow::MainWindow(QWidget* parent)
    : QMainWindow(parent), menus_(std::make_unique<Menus>()) {
    using namespace mr::constants::Ui;

    // Pascal: Main.dfm ClientWidth=700, ClientHeight=413. Those are
    // CONTENT dimensions; the macOS title bar gets added on top. To
    // get a 700x413 *client* area we size the central widget, then
    // let the window auto-fit and lock its size afterward.
    setWindowTitle(QStringLiteral("Morse Runner"));
    setWindowFlags(windowFlags() & ~Qt::WindowMaximizeButtonHint
                                  & ~Qt::WindowMinimizeButtonHint);

    buildMenus();
    buildCentralLayout();

    // Pascal KeyPreview: see keys before the focused control.
    qApp->installEventFilter(this);
}

MainWindow::~MainWindow() = default;

void MainWindow::buildCentralLayout() {
    using namespace mr::constants::Ui;
    auto* central = new QWidget(this);
    central->setFixedSize(kMainWindowWidth, kMainWindowHeight);

    rightPanel_ = new RightPanel(menus_->runPopup, central);
    rightPanel_->move(kMainWindowWidth - kRightPanelWidth, kTopBevelHeight);

    bottomPanel_ = new BottomPanel(central);
    bottomPanel_->move(0, kMainWindowHeight - kBottomPanelHeight);
    bottomPanel_->setFixedWidth(kMainWindowWidth);

    logView_ = new LogView(central);
    const int logX = 0;
    const int logY = kTopBevelHeight;
    const int logW = kMainWindowWidth - kRightPanelWidth;
    const int logH = kMainWindowHeight - kBottomPanelHeight - kTopBevelHeight;
    logView_->setGeometry(logX, logY, logW, logH);

    // Pascal ToolButton1: AllowAllUp/Grouped — shown "down" while a run
    // is going (SetToolbuttonDown); the caption stays "Run".
    if (auto* rb = rightPanel_->runButton(); rb != nullptr) {
        rb->setCheckable(true);
        rb->setText(QStringLiteral("   Run   "));
    }

    // Cache F-key button pointers so AppController can iterate them.
    for (int i = 0; i < 8; ++i) {
        fKeyButtons_[i] = bottomPanel_->fKeyButton(i);
    }

    setCentralWidget(central);
    adjustSize();
    setFixedSize(size());

    // Phase-E wiring: collapse menu + matching checkbox clicks into
    // single MainWindow signals, sync the menu checkmark with the
    // right-panel checkbox state, hook F-keys to sendMessageRequested.
    wireMenuFanouts();
    wireBottomPanelClicks();
    wireCheckBoxSync();
    wireNumericSettings();
}

void MainWindow::buildMenus() {
    buildFileMenu();
    buildRunMenu();
    buildSendMenu();
    buildSettingsMenu();
    buildHelpMenu();
}

void MainWindow::buildFileMenu() {
    // Pascal: Main.dfm MainMenu1.File1 — five entries with two separators.
    menus_->file = menuBar()->addMenu(QStringLiteral("&File"));
    menus_->viewScoreTable = menus_->file->addAction(
        QStringLiteral("View Score Table"));
    menus_->viewHiScoreWebPage = menus_->file->addAction(
        QStringLiteral("View Hi-Score web page..."));
    menus_->file->addSeparator();
    menus_->audioRecordingEnabled = menus_->file->addAction(
        QStringLiteral("Audio Recording Enabled"));
    menus_->audioRecordingEnabled->setCheckable(true);
    menus_->playRecordedAudio = menus_->file->addAction(
        QStringLiteral("Play Recorded Audio"));
    // Pascal: initially disabled until a recording exists.
    menus_->playRecordedAudio->setEnabled(false);
    menus_->file->addSeparator();
    menus_->exit = menus_->file->addAction(QStringLiteral("Exit"));
    menus_->exit->setMenuRole(QAction::QuitRole);
    connect(menus_->exit, &QAction::triggered, this, &QMainWindow::close);

    // Pascal File → View Hi-Score web page... opens MrScore.asp in
    // the system browser.
    connect(menus_->viewHiScoreWebPage, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl(QStringLiteral(
            "http://www.dxatlas.com/MorseRunner/MrScore.asp")));
    });
    // Pascal File → View Score Table replaces the log RichEdit's
    // contents with the per-user .lst score history (one Pascal-format
    // submission line per past WPX run). Empty file → "Your score
    // table is empty". Pascal writes to ChangeFileExt(exe, '.lst');
    // we use ~/Library/Application Support/MorseRunner/scores.lst.
    connect(menus_->viewScoreTable, &QAction::triggered, this, [this]() {
        if (logView_ == nullptr) return;
        logView_->clear();
        const QString path = scoreHistoryPath();
        QFile f(path);
        if (f.exists() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString text = QString::fromUtf8(f.readAll());
            logView_->setPlainText(text);
        } else {
            logView_->setPlainText(QStringLiteral("Your score table is empty"));
        }
    });
    // Pascal File → Audio Recording Enabled. Toggle persists to the
    // plist and emits audioRecordingToggled(on, path) so AppController
    // can hand it to the sim worker via queued connection. We compute
    // the destination path on the GUI thread (QStandardPaths is GUI-
    // thread-safe) so the sim thread sees a ready-to-open absolute
    // path. The companion File → Play Recorded Audio action's enabled
    // state mirrors whether the WAV exists on disk.
    menus_->audioRecordingEnabled->setCheckable(true);
    connect(menus_->audioRecordingEnabled, &QAction::toggled,
            this, [this](bool on) {
        const QString path = recordedAudioPath();
        // Ensure the directory exists before the sim thread opens
        // the file for write — otherwise WavWriter::open silently
        // fails and recording starts disabled with no feedback.
        QDir().mkpath(QFileInfo(path).absolutePath());
        emit audioRecordingToggled(on, path);
        if (menus_->playRecordedAudio != nullptr) {
            menus_->playRecordedAudio->setEnabled(
                !on && QFileInfo::exists(path));
        }
    });
    // Pascal File → Play Recorded Audio. ShellExecute opens the WAV
    // in the system's default audio player; QDesktopServices is the
    // direct equivalent and avoids spinning up our own QMediaPlayer
    // (which would compete with the contest's QAudioSink anyway).
    connect(menus_->playRecordedAudio, &QAction::triggered, this, [this]() {
        const QString path = recordedAudioPath();
        if (QFileInfo::exists(path)) {
            QDesktopServices::openUrl(QUrl::fromLocalFile(path));
        }
    });
    if (menus_->playRecordedAudio != nullptr) {
        menus_->playRecordedAudio->setEnabled(
            QFileInfo::exists(recordedAudioPath()));
    }
}

void MainWindow::buildRunMenu() {
    // Pascal: MainMenu1.Run1 — five entries (4 modes + Stop) with a
    // separator. Pile-Up has F8 shortcut, HST has Ctrl+F8. Group as
    // exclusive radio so the active mode is visually obvious.
    menus_->run = menuBar()->addMenu(QStringLiteral("&Run"));
    auto* group = new QActionGroup(this);
    group->setExclusive(true);

    menus_->runPileUp = menus_->run->addAction(QStringLiteral("Pile-Up"));
    menus_->runPileUp->setCheckable(true);
    // Main.dfm also gives Pile-Up F8, colliding with Send > NIL (F8).
    // NIL is the operating key, so it keeps F8; the Run button body
    // starts Pile-Up in one click. See docs/parity-checklist.md.
    group->addAction(menus_->runPileUp);

    menus_->runSingleCalls = menus_->run->addAction(QStringLiteral("Single Calls"));
    menus_->runSingleCalls->setCheckable(true);
    group->addAction(menus_->runSingleCalls);

    menus_->runWpx = menus_->run->addAction(QStringLiteral("WPX Competition"));
    menus_->runWpx->setCheckable(true);
    group->addAction(menus_->runWpx);

    menus_->runHst = menus_->run->addAction(QStringLiteral("HST Competition"));
    menus_->runHst->setCheckable(true);
    menus_->runHst->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_F8));
    group->addAction(menus_->runHst);

    menus_->run->addSeparator();
    menus_->runStop = menus_->run->addAction(QStringLiteral("Stop"));
    menus_->runStop->setEnabled(false);

    for (QAction* a : {menus_->runPileUp, menus_->runSingleCalls,
                       menus_->runWpx, menus_->runHst, menus_->runStop}) {
        connect(a, &QAction::triggered, this, &MainWindow::onPlaceholderAction);
    }

    // Pascal: PopupMenu1 attached to the Run toolbar button (Panel10).
    // We rebuild a parallel QMenu and let the toolbar button in D.G2
    // attach it via setMenu().
    menus_->runPopup = new QMenu(this);
    menus_->runPopup->addAction(menus_->runPileUp);
    menus_->runPopup->addAction(menus_->runSingleCalls);
    menus_->runPopup->addAction(menus_->runWpx);
    menus_->runPopup->addAction(menus_->runHst);
    menus_->runPopup->addSeparator();
    menus_->runPopup->addAction(menus_->runStop);
}

void MainWindow::buildSendMenu() {
    // Pascal: MainMenu1.Send1 — F1..F8 shortcuts for the eight
    // contest messages. Phase E wires each to
    // Sim::Contest::playerSendMessage(<Message>).
    menus_->send = menuBar()->addMenu(QStringLiteral("&Send"));

    auto addSend = [&](const QString& label, QKeySequence shortcut) {
        auto* a = menus_->send->addAction(label);
        a->setShortcut(shortcut);
        connect(a, &QAction::triggered, this, &MainWindow::onPlaceholderAction);
        return a;
    };

    menus_->sendCq      = addSend(QStringLiteral("CQ"),      QKeySequence(Qt::Key_F1));
    menus_->sendNumber  = addSend(QStringLiteral("Number"),  QKeySequence(Qt::Key_F2));
    menus_->sendTu      = addSend(QStringLiteral("TU"),      QKeySequence(Qt::Key_F3));
    menus_->sendMyCall  = addSend(QStringLiteral("My Call"), QKeySequence(Qt::Key_F4));
    menus_->sendHisCall = addSend(QStringLiteral("His Call"),QKeySequence(Qt::Key_F5));
    menus_->sendQsoB4   = addSend(QStringLiteral("QSO B4"),  QKeySequence(Qt::Key_F6));
    menus_->sendQm      = addSend(QStringLiteral("<?>"),     QKeySequence(Qt::Key_F7));
    menus_->sendNil     = addSend(QStringLiteral("NIL"),     QKeySequence(Qt::Key_F8));
}

void MainWindow::buildSettingsMenu() {
    using namespace mr::constants::Ui;
    menus_->settings = menuBar()->addMenu(QStringLiteral("Se&ttings"));

    menus_->settingsCall = menus_->settings->addAction(QStringLiteral("Call..."));
    connect(menus_->settingsCall, &QAction::triggered, this,
            &MainWindow::onPlaceholderAction);

    menus_->settingsQsk = menus_->settings->addAction(QStringLiteral("QSK"));
    menus_->settingsQsk->setCheckable(true);
    menus_->settingsQsk->setChecked(true);
    connect(menus_->settingsQsk, &QAction::triggered, this,
            &MainWindow::onPlaceholderAction);

    // CW Speed: 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 WPM
    menus_->cwSpeedMenu = menus_->settings->addMenu(QStringLiteral("CW Speed"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        addNumericChoices(
            menus_->cwSpeedMenu,
            {10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60},
            QStringLiteral("WPM"), group,
            &MainWindow::onPlaceholderAction, this);
    }

    // CW Pitch: 300..900 Hz step 50 (13 items).
    menus_->cwPitchMenu = menus_->settings->addMenu(QStringLiteral("CW Pitch"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        for (int hz = kPitchMinHz; hz <= kPitchMaxHz; hz += kPitchStepHz) {
            auto* act = menus_->cwPitchMenu->addAction(
                QStringLiteral("%1 Hz").arg(hz));
            act->setCheckable(true);
            act->setData(hz);
            group->addAction(act);
            connect(act, &QAction::triggered, this,
                    &MainWindow::onPlaceholderAction);
        }
    }

    // CW Bandwidth: 100..600 Hz step 50 (11 items).
    menus_->cwBandwidthMenu =
        menus_->settings->addMenu(QStringLiteral("CW Bandwidth"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        for (int hz = kBandwidthMinHz; hz <= kBandwidthMaxHz;
             hz += kBandwidthStepHz) {
            auto* act = menus_->cwBandwidthMenu->addAction(
                QStringLiteral("%1 Hz").arg(hz));
            act->setCheckable(true);
            act->setData(hz);
            group->addAction(act);
            connect(act, &QAction::triggered, this,
                    &MainWindow::onPlaceholderAction);
        }
    }

    // Mon. Level: -60, -40, -20, 0, +20 dB.
    menus_->monLevelMenu =
        menus_->settings->addMenu(QStringLiteral("Mon. Level"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        for (int db : {-60, -40, -20, 0, 20}) {
            auto* act = menus_->monLevelMenu->addAction(
                QStringLiteral("%1 dB").arg(db));
            act->setCheckable(true);
            act->setData(db);
            group->addAction(act);
            connect(act, &QAction::triggered, this,
                    &MainWindow::onPlaceholderAction);
        }
    }

    menus_->settings->addSeparator();

    auto addToggle = [&](const QString& label, bool initial) {
        auto* a = menus_->settings->addAction(label);
        a->setCheckable(true);
        a->setChecked(initial);
        connect(a, &QAction::triggered, this,
                &MainWindow::onPlaceholderAction);
        return a;
    };
    menus_->settingsQrn     = addToggle(QStringLiteral("QRN"),     true);
    menus_->settingsQrm     = addToggle(QStringLiteral("QRM"),     true);
    menus_->settingsQsb     = addToggle(QStringLiteral("QSB"),     true);
    menus_->settingsFlutter = addToggle(QStringLiteral("Flutter"), true);
    menus_->settingsLids    = addToggle(QStringLiteral("LIDs"),    true);

    // Activity: 1..9.
    menus_->activityMenu = menus_->settings->addMenu(QStringLiteral("Activity"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        for (int i = kActivityMin; i <= kActivityMax; ++i) {
            auto* act = menus_->activityMenu->addAction(QString::number(i));
            act->setCheckable(true);
            act->setData(i);
            group->addAction(act);
            connect(act, &QAction::triggered, this,
                    &MainWindow::onPlaceholderAction);
        }
    }

    menus_->settings->addSeparator();

    // Duration: 5, 10, 15, 30, 60, 90, 120 minutes.
    menus_->durationMenu = menus_->settings->addMenu(QStringLiteral("Duration"));
    {
        auto* group = new QActionGroup(this);
        group->setExclusive(true);
        for (int m : {5, 10, 15, 30, 60, 90, 120}) {
            auto* act = menus_->durationMenu->addAction(
                QStringLiteral("%1 min").arg(m));
            act->setCheckable(true);
            act->setData(m);
            group->addAction(act);
            connect(act, &QAction::triggered, this,
                    &MainWindow::onPlaceholderAction);
        }
    }

    menus_->settingsHstOperator =
        menus_->settings->addAction(QStringLiteral("HST Operator..."));
    // Pascal Operator1Click pops an InputBox asking for the
    // operator's name, persists to SEC_STN/Name in the ini, and
    // appends the name to the window title.
    connect(menus_->settingsHstOperator, &QAction::triggered, this, [this]() {
        mr::persistence::Settings settings;
        const QString current = settings.hamName();
        bool ok = false;
        const QString entered = QInputDialog::getText(
            this,
            QStringLiteral("HST Operator"),
            QStringLiteral("Enter operator's name"),
            QLineEdit::Normal, current, &ok);
        if (!ok) {
            return;
        }
        settings.setHamName(entered);
        applyHamNameToTitle(entered);
    });
}

void MainWindow::buildHelpMenu() {
    menus_->help = menuBar()->addMenu(QStringLiteral("&Help"));
    menus_->helpWebPage = menus_->help->addAction(QStringLiteral("Web Page..."));
    menus_->helpReadme  = menus_->help->addAction(QStringLiteral("Readme..."));
    menus_->help->addSeparator();
    menus_->helpAbout   = menus_->help->addAction(QStringLiteral("About..."));
    menus_->helpAbout->setMenuRole(QAction::AboutRole);

    // Pascal Main.OpenWebPage uses ShellExecute to open the URL in the
    // user's browser. QDesktopServices::openUrl is the Qt equivalent.
    connect(menus_->helpWebPage, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl(QStringLiteral(
            "http://www.dxatlas.com/MorseRunner/")));
    });
    // Pascal opens Readme.txt with the default text viewer. We bundle
    // it in Resources/docs.
    connect(menus_->helpReadme, &QAction::triggered, this, []() {
        const QString path = QCoreApplication::applicationDirPath()
            + QStringLiteral("/../Resources/docs/Readme.txt");
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    });
    // About is the one Help item with a real Phase-D handler — opens
    // the MPL-summary AboutDialog. Web page + Readme stay inert until
    // Phase F wires URL opening / readme display.
    connect(menus_->helpAbout, &QAction::triggered, this, [this]() {
        AboutDialog dlg(this);
        dlg.exec();
    });
}

void MainWindow::onPlaceholderAction() {
    if (auto* act = qobject_cast<QAction*>(sender()); act != nullptr) {
        qInfo(mrUi).noquote() << "menu:" << act->text() << "data=" << act->data();
    }
}

void MainWindow::onClockTicked(double seconds) {
    // Pascal GetAudio, every block while running:
    //   Panel2.Caption := FormatDateTime('hh:nn:ss', BlocksToSeconds(..))
    //   ShowRate
    // FormatDateTime rounds to the millisecond and drops the rest.
    elapsedSeconds_ = seconds;
    const long long totalSec = std::llround(seconds * 1000.0) / 1000;
    const QString text = QStringLiteral("%1:%2:%3")
        .arg(static_cast<int>((totalSec / 3600) % 24), 2, 10, QChar('0'))
        .arg(static_cast<int>((totalSec / 60) % 60), 2, 10, QChar('0'))
        .arg(static_cast<int>(totalSec % 60), 2, 10, QChar('0'));
    if (auto* lbl = bottomPanel_->clockLabel(); lbl != nullptr) {
        lbl->setText(text);
    }
    if (runMode_ != static_cast<int>(mr::sim::RunMode::Stop)) {
        refreshRateAndHistogram();
    }
}

void MainWindow::applyHamNameToTitle(const QString& name) {
    if (name.isEmpty()) {
        setWindowTitle(QStringLiteral("Morse Runner"));
    } else {
        setWindowTitle(QStringLiteral("Morse Runner:  %1").arg(name));
    }
}

QString MainWindow::scoreHistoryPath() const {
    const QString dir = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    return dir + QStringLiteral("/scores.lst");
}

QString MainWindow::recordedAudioPath() const {
    const QString dir = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    return dir + QStringLiteral("/MorseRunner.wav");
}

QString MainWindow::hstResultsPath() const {
    // Pascal: ExtractFilePath(ParamStr(0)) + 'HstResults.txt'.
    const QString dir = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    return dir + QStringLiteral("/HstResults.txt");
}

void MainWindow::appendLine(const QString& path, const QString& line) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        f.write(line.toUtf8());
        f.write("\n");
    }
}

void MainWindow::onContestEnded(int mode, bool stoppedByUser) {
    // Pascal Contest.GetAudio end-of-run block:
    //   HST            → Run(rmStop); PopupScoreHst   (timer or Stop)
    //   WPX, timer ran → Run(rmStop); PopupScoreWpx
    //   anything else  → Run(rmStop)
    using mr::sim::RunMode;
    const auto runMode = static_cast<RunMode>(mode);
    setRunning(static_cast<int>(RunMode::Stop));

    mr::persistence::Settings settings;
    QString myCall;
    if (auto* rp = rightPanel_; rp != nullptr && rp->callEdit() != nullptr) {
        myCall = rp->callEdit()->text();
    }

    if (runMode == RunMode::Hst) {
        // PopupScoreHst: append "yyyy-mm-dd hh:nn<TAB>Call<TAB>Name<TAB>Score"
        // to HstResults.txt, then ShowMessage('HST Score: ' + verified).
        const auto st = log_.stats(true);
        const QString line = QStringLiteral("%1\t%2\t%3\t%4")
            .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm")),
                 myCall, settings.hamName(), QString::number(st.verified.score));
        appendLine(hstResultsPath(), line);
        QMessageBox::information(this, QStringLiteral("Morse Runner"),
                                 QStringLiteral("HST Score: %1").arg(st.verified.score));
        return;
    }
    if (runMode != RunMode::Wpx || stoppedByUser) {
        return;
    }

    // PopupScoreWpx: "yyyy-mm-dd <call> <verified pts> <verified mult> "
    // + "[CRC32]" with seed 0xC90C2086; append to the .lst history.
    const auto st = log_.stats(false);
    const QString inner = QStringLiteral("%1 %2 %3 %4 ")
        .arg(QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd")), myCall,
             QString::number(st.verified.pts), QString::number(st.verified.mul));
    const std::uint32_t crc = mr::scoring::calculateCrc32(
        inner.toStdString(), static_cast<std::uint32_t>(0xC90C2086U));
    const QString stamped = inner + QStringLiteral("[%1]").arg(crc, 8, 16, QChar('0')).toUpper();
    appendLine(scoreHistoryPath(), stamped);

    const int score = st.verified.score;
    const int prevHi = settings.hiScore();
    const bool newHi = score > prevHi;
    if (newHi) {
        settings.setHiScore(score);
    }
    ScoreDialog dlg(stamped, newHi, this);
    dlg.exec();
}

void MainWindow::onDxQsoCompleted(const QString& call, int rst, int nr,
                                  float /*minute*/) {
    // Pascal Contest.GetAudio: the DX matching the last QSO hands over
    // its record (DataToLastQso); the last log line is deleted, CheckErr
    // runs again, the line is redrawn and the stats recomputed.
    if (log_.applyTruth(call.toStdString(), rst, nr)) {
        showLastQso(true);
    }
}

bool MainWindow::hstMode() const noexcept {
    return runMode_ == static_cast<int>(mr::sim::RunMode::Hst);
}

void MainWindow::showLastQso(bool replaceRow) {
    if (log_.empty() || logView_ == nullptr) {
        return;
    }
    // Me.Rst is always 599 for the player.
    const QString row = QString::fromStdString(log_.formatRow(log_.qsos().size() - 1, 599));
    if (replaceRow) {
        logView_->replaceLastQsoRow(row);
    } else {
        logView_->appendQsoRow(row, row.right(3));
    }
    refreshStats();
}

void MainWindow::refreshStats() {
    // Pascal UpdateStats / UpdateStatsHst.
    const bool hst = hstMode();
    const auto st = log_.stats(hst);
    auto set = [this](int r, int c, const QString& v) {
        if (auto* lbl = bottomPanel_->scoreCell(r, c)) {
            lbl->setText(v);
        }
    };
    if (hst) {
        set(0, 0, {});
        set(1, 0, {});
        set(0, 1, {});
        set(1, 1, {});
        set(2, 0, QString::number(st.raw.score));
        set(2, 1, QString::number(st.verified.score));
        bottomPanel_->setHstScore(st.verified.score);
    } else {
        set(0, 0, QString::number(st.raw.pts));
        set(1, 0, QString::number(st.raw.mul));
        set(2, 0, QString::number(st.raw.score));
        set(0, 1, QString::number(st.verified.pts));
        set(1, 1, QString::number(st.verified.mul));
        set(2, 1, QString::number(st.verified.score));
    }
    if (auto* hist = bottomPanel_->histogramPanel()) {
        hist->setAllBins(log_.histogram());
    }
}

void MainWindow::refreshRateAndHistogram() {
    // Pascal ShowRate (no label change until time has elapsed).
    if (const auto r = log_.rate(elapsedSeconds_); r.has_value()) {
        if (auto* rate = bottomPanel_->rateLabel()) {
            rate->setText(QStringLiteral("%1  qso/hr.").arg(*r));
        }
    }
}

// ─── Main.pas operating logic ───────────────────────────────────────────

void MainWindow::sendMsg(int message) {
    // Pascal TMainForm.SendMsg: HisCall keys the Call box (when not
    // empty) and sets CallSent; NR sets NrSent.
    using mr::sim::Message;
    const auto m = static_cast<Message>(message);
    QString callField;
    if (m == Message::HisCall) {
        callField = bottomPanel_->callEdit()->text();
        callSent_ = true;
        // Edits typed before this send are already reflected in it;
        // ignore their late UpdateCallInMessage answers.
        ignoredCallEditResults_ = pendingCallEditResults_;
    }
    if (m == Message::Nr) {
        nrSent_ = true;
    }
    emit sendMessageRequested(message, callField);
}

void MainWindow::wipeBoxes() {
    // Pascal TMainForm.WipeBoxes.
    bottomPanel_->callEdit()->clear();
    bottomPanel_->rstEdit()->clear();
    bottomPanel_->nrEdit()->clear();
    bottomPanel_->callEdit()->setFocus();
    callSent_ = false;
    nrSent_ = false;
}

void MainWindow::processSpace() {
    // Pascal TMainForm.ProcessSpace: Call → Nr, RST → Nr (filling an
    // empty RST with 599), Nr → Call.
    mustAdvance_ = false;
    auto* call = bottomPanel_->callEdit();
    auto* rst = bottomPanel_->rstEdit();
    auto* nr = bottomPanel_->nrEdit();
    QWidget* fw = focusWidget();
    if (fw == call || fw == rst) {
        if (rst->text().isEmpty()) {
            rst->setText(QStringLiteral("599"));
        }
        nr->setFocus();
    } else {
        call->setFocus();
    }
}

void MainWindow::processEnter(bool forceSave) {
    // Pascal TMainForm.ProcessEnter — ESM (Enter Sends Messages).
    using mr::sim::Message;
    mustAdvance_ = false;

    // Ctrl / Shift / Alt + Enter: save only.
    if (forceSave) {
        saveQso();
        return;
    }
    // No QSO in progress: send CQ.
    if (bottomPanel_->callEdit()->text().isEmpty()) {
        sendMsg(static_cast<int>(Message::Cq));
        return;
    }

    const bool c = callSent_;
    const bool n = nrSent_;
    const bool r = !bottomPanel_->nrEdit()->text().isEmpty();

    // Send his call if not sent before, or if the call changed.
    if (!c || (!n && !r)) {
        sendMsg(static_cast<int>(Message::HisCall));
    }
    if (!n) {
        sendMsg(static_cast<int>(Message::Nr));
    }
    if (n && !r) {
        sendMsg(static_cast<int>(Message::Qm));
    }

    if (r && (c || n)) {
        sendMsg(static_cast<int>(Message::Tu));
        saveQso();
    } else {
        mustAdvance_ = true;
    }
}

void MainWindow::onPlayerPieceFinished() {
    // Pascal TMainForm.Advance.
    if (!mustAdvance_) {
        return;
    }
    auto* call = bottomPanel_->callEdit();
    auto* rst = bottomPanel_->rstEdit();
    if (rst->text().isEmpty()) {
        rst->setText(QStringLiteral("599"));
    }
    if (!call->text().contains(QLatin1Char('?'))) {
        bottomPanel_->nrEdit()->setFocus();
    } else if (focusWidget() == call) {
        selectCallQuestionMark();
    } else {
        call->setFocus();
    }
    mustAdvance_ = false;
}

void MainWindow::selectCallQuestionMark() {
    // Pascal Edit1Enter: select the first '?' (unless it is the first
    // character) so typing replaces it.
    auto* call = bottomPanel_->callEdit();
    const auto p = call->text().indexOf(QLatin1Char('?'));
    if (p > 0) {
        call->setSelection(static_cast<int>(p), 1);
    }
}

void MainWindow::onCallEditResult(const QString& /*callField*/, bool applied) {
    // Pascal Edit1Change: if not Tst.Me.UpdateCallInMessage(...) then
    // CallSent := false.
    if (pendingCallEditResults_ > 0) {
        --pendingCallEditResults_;
    }
    if (ignoredCallEditResults_ > 0) {
        --ignoredCallEditResults_;
        return;
    }
    if (!applied) {
        callSent_ = false;
    }
}

void MainWindow::onSendAborted(bool hadHisCall, bool hadNr) {
    // Pascal FormKeyPress #27: clear the flags for whatever was being
    // (or was last) sent.
    if (hadHisCall) {
        callSent_ = false;
    }
    if (hadNr) {
        nrSent_ = false;
    }
}

void MainWindow::saveQso() {
    // Pascal Log.SaveQso (GUI half; the DX lookup and Inc(Me.NR) run
    // on the sim thread via qsoLogged).
    auto* call = bottomPanel_->callEdit();
    auto* rst = bottomPanel_->rstEdit();
    auto* nr = bottomPanel_->nrEdit();
    const std::string callText = call->text().toStdString();
    if (!mr::scoring::QsoLog::entryIsValid(callText, rst->text().toStdString(),
                                           nr->text().toStdString())) {
        QApplication::beep();
        return;
    }
    const auto& q = log_.add(elapsedSeconds_, callText, rst->text().toInt(),
                             nr->text().toInt(), hstMode());
    const QString loggedCall = QString::fromStdString(q.call);
    showLastQso(false);
    emit qsoLogged(loggedCall);
    wipeBoxes();
}

void MainWindow::incSpeed() {
    // Pascal IncSpeed: next multiple of 5 up, clamped 10..120.
    auto* spin = rightPanel_->wpmSpin();
    const int wpm = (spin->value() / 5) * 5 + 5;
    spin->setValue(std::clamp(wpm, 10, 120));
}

void MainWindow::decSpeed() {
    // Pascal DecSpeed: previous multiple of 5 down, clamped 10..120.
    auto* spin = rightPanel_->wpmSpin();
    const int wpm = ((spin->value() + 4) / 5) * 5 - 5;
    spin->setValue(std::clamp(wpm, 10, 120));
}

void MainWindow::stepBandwidth(int delta) {
    // Pascal SetBw(ComboBox2.ItemIndex ± 1): ignored outside the list.
    auto* combo = rightPanel_->bandwidthCombo();
    const int idx = combo->currentIndex() + delta;
    if (idx >= 0 && idx < combo->count()) {
        combo->setCurrentIndex(idx);
    }
}

void MainWindow::incRit(int step) {
    // Pascal IncRit: -1 / +1 move 50 Hz, 0 resets; clamped ±500.
    if (auto* rs = bottomPanel_->ritSlider(); rs != nullptr) {
        const int hz = (step == 0) ? 0 : rs->ritHz() + step * 50;
        rs->setRitHz(std::clamp(hz, -500, 500));
    }
}

bool MainWindow::eventFilter(QObject* watched, QEvent* event) {
    // Pascal KeyPreview: FormKeyPress / FormKeyDown see every key in the
    // window before the focused control.
    if (event->type() == QEvent::FocusIn && bottomPanel_ != nullptr) {
        // Pascal Edit1Enter / Edit2Enter (AutoSelect is off). Deferred
        // so it lands after QLineEdit's own focus-in selection.
        if (watched == bottomPanel_->callEdit()) {
            QTimer::singleShot(0, this, [this]() { selectCallQuestionMark(); });
        } else if (watched == bottomPanel_->rstEdit()) {
            QTimer::singleShot(0, this, [this]() {
                auto* rst = bottomPanel_->rstEdit();
                if (rst->text().size() == 3) {
                    rst->setSelection(1, 1);
                }
            });
        }
        return false;
    }
    if (event->type() != QEvent::KeyPress) {
        return false;
    }
    auto* w = qobject_cast<QWidget*>(watched);
    if (w == nullptr || w->window() != this || bottomPanel_ == nullptr) {
        return false;
    }
    using mr::sim::Message;
    auto* ke = static_cast<QKeyEvent*>(event);
    int key = ke->key();
    // macOS: Qt::ControlModifier is Cmd and Qt::MetaModifier is the
    // Control key. Pascal's "Ctrl" accepts either here (several Ctrl
    // combos, e.g. Ctrl-Up, are taken by macOS itself).
    const auto mods = ke->modifiers() & ~Qt::KeypadModifier;
    const bool ctrl = (mods & (Qt::ControlModifier | Qt::MetaModifier)) != 0;
    const bool alt = (mods & Qt::AltModifier) != 0;
    const bool shift = (mods & Qt::ShiftModifier) != 0;
    // Option-W can arrive as the composed character ("∑"); match the
    // physical W key (kVK_ANSI_W = 13) instead.
    constexpr quint32 kMacVirtualKeyW = 13;
    if ((alt || ctrl) && ke->nativeVirtualKey() == kMacVirtualKeyW) {
        key = Qt::Key_W;
    }

    // ── FormKeyDown (virtual keys) ──
    switch (key) {
        case Qt::Key_Insert:                       // <his> <#>
            sendMsg(static_cast<int>(Message::HisCall));
            sendMsg(static_cast<int>(Message::Nr));
            return true;
        case Qt::Key_Return:
        case Qt::Key_Enter:
            processEnter(ctrl || shift || alt);
            return true;
        case Qt::Key_F11:
            wipeBoxes();
            return true;
        case Qt::Key_W:
            if (alt || ctrl) {                     // Alt-W, ^W
                wipeBoxes();
                return true;
            }
            break;
        case Qt::Key_Up:
        case Qt::Key_Down: {
            const int dir = (key == Qt::Key_Up) ? 1 : -1;
            if (!ctrl) {
                incRit(dir);
            } else if (!hstMode()) {
                stepBandwidth(dir);
            }
            return true;
        }
        case Qt::Key_PageUp:
            incSpeed();
            return true;
        case Qt::Key_PageDown:
            decSpeed();
            return true;
        case Qt::Key_F9:
        case Qt::Key_F10:
            if (alt || ctrl) {
                (key == Qt::Key_F10) ? incSpeed() : decSpeed();
                return true;
            }
            break;
        case Qt::Key_Escape: {                     // FormKeyPress #27
            emit abortSendRequested();
            return true;
        }
        default:
            break;
    }

    // ── FormKeyPress (characters) ──
    if (ctrl || alt) {
        return false;
    }
    const QString text = ke->text();
    if (text.size() != 1) {
        return false;
    }
    switch (text.at(0).unicode()) {
        case ';':                                  // <his> <#>
            sendMsg(static_cast<int>(Message::HisCall));
            sendMsg(static_cast<int>(Message::Nr));
            return true;
        case '.':
        case '+':
        case '[':
        case ',':                                  // TU & save
            if (!callSent_) {
                sendMsg(static_cast<int>(Message::HisCall));
            }
            sendMsg(static_cast<int>(Message::Tu));
            saveQso();
            return true;
        case ' ':
            processSpace();
            return true;
        case '\\':                                 // = F1
            sendMsg(static_cast<int>(Message::Cq));
            return true;
        default:
            return false;
    }
}

// ─── Phase-E action accessors ───────────────────────────────────────
// AppController uses these to connect MainWindow's high-level signals
// to the SimulationWorker slots without poking into Menus internals.

QAction* MainWindow::runPileUpAction() const noexcept { return menus_->runPileUp; }
QAction* MainWindow::runSingleAction() const noexcept { return menus_->runSingleCalls; }
QAction* MainWindow::runWpxAction()    const noexcept { return menus_->runWpx; }
QAction* MainWindow::runHstAction()    const noexcept { return menus_->runHst; }
QAction* MainWindow::runStopAction()   const noexcept { return menus_->runStop; }
QAction* MainWindow::audioRecordingAction() const noexcept {
    return menus_->audioRecordingEnabled;
}

QAction* MainWindow::sendAction(int fKeyIndex) const noexcept {
    switch (fKeyIndex) {
        case 0: return menus_->sendCq;
        case 1: return menus_->sendNumber;
        case 2: return menus_->sendTu;
        case 3: return menus_->sendMyCall;
        case 4: return menus_->sendHisCall;
        case 5: return menus_->sendQsoB4;
        case 6: return menus_->sendQm;
        case 7: return menus_->sendNil;
        default: return nullptr;
    }
}

QAction* MainWindow::qrnAction()     const noexcept { return menus_->settingsQrn; }
QAction* MainWindow::qrmAction()     const noexcept { return menus_->settingsQrm; }
QAction* MainWindow::qsbAction()     const noexcept { return menus_->settingsQsb; }
QAction* MainWindow::flutterAction() const noexcept { return menus_->settingsFlutter; }
QAction* MainWindow::lidsAction()    const noexcept { return menus_->settingsLids; }
QAction* MainWindow::qskAction()     const noexcept { return menus_->settingsQsk; }

QPushButton* MainWindow::fKeyButton(int index) const noexcept {
    return (index >= 0 && index < 8) ? fKeyButtons_[index] : nullptr;
}

// ─── Phase-E signal fan-out ─────────────────────────────────────────

void MainWindow::wireMenuFanouts() {
    using mr::sim::Message;
    using mr::sim::RunMode;

    // Pascal RunMNUClick → Run(Tag); StopMNUClick → Tst.FStopPressed.
    auto run = [this](RunMode m) { setRunning(static_cast<int>(m)); };
    connect(menus_->runPileUp, &QAction::triggered, this, [run]() { run(RunMode::PileUp); });
    connect(menus_->runSingleCalls, &QAction::triggered, this, [run]() { run(RunMode::Single); });
    connect(menus_->runWpx, &QAction::triggered, this, [run]() { run(RunMode::Wpx); });
    connect(menus_->runHst, &QAction::triggered, this, [run]() { run(RunMode::Hst); });
    connect(menus_->runStop, &QAction::triggered, this, [this]() { emit stopRequested(); });

    // Pascal RunBtnClick: Pile-Up when stopped, else FStopPressed.
    if (auto* rb = rightPanel_->runButton(); rb != nullptr) {
        connect(rb, &QToolButton::clicked, this, [this]() {
            if (runMode_ == static_cast<int>(mr::sim::RunMode::Stop)) {
                setRunning(static_cast<int>(mr::sim::RunMode::PileUp));
            } else {
                emit stopRequested();
            }
            // Pascal SetToolbuttonDown: the button is "down" exactly
            // while a run is going; undo Qt's click toggle.
            if (auto* b = rightPanel_->runButton()) {
                b->setChecked(runMode_ != static_cast<int>(mr::sim::RunMode::Stop));
            }
        });
    }

    // Send menu (F1..F8) → SendClick → SendMsg.
    static constexpr Message kSendMap[8] = {
        Message::Cq,  Message::Nr,  Message::Tu,    Message::MyCall,
        Message::HisCall, Message::B4, Message::Qm, Message::Nil,
    };
    for (int i = 0; i < 8; ++i) {
        if (auto* a = sendAction(i); a != nullptr) {
            const Message m = kSendMap[i];
            connect(a, &QAction::triggered, this,
                    [this, m]() { sendMsg(static_cast<int>(m)); });
        }
    }

    // Settings toggles (QRN/QRM/QSB/Flutter/LIDs/QSK) emit their
    // *Toggled signals via the checkbox bridge in wireCheckBoxSync —
    // connecting the actions here as well would emit every change twice.
}

void MainWindow::setRunning(int mode) {
    // Pascal TMainForm.Run(Value).
    using mr::sim::RunMode;
    if (mode == runMode_) {
        return;
    }
    const auto value = static_cast<RunMode>(mode);
    const bool bStop = value == RunMode::Stop;
    const bool bCompet = value == RunMode::Wpx || value == RunMode::Hst;
    const bool hst = value == RunMode::Hst;
    runMode_ = mode;
    auto* rp = rightPanel_;

    // Main controls.
    rp->callEdit()->setEnabled(bStop);
    rp->durationSpin()->setEnabled(bStop);
    if (auto* rb = rp->runButton()) {
        rb->setChecked(!bStop);
    }

    // Band-condition checkboxes: fixed in competition modes.
    for (QCheckBox* cb : {rp->qsbCheckBox(), rp->qrmCheckBox(), rp->qrnCheckBox(),
                          rp->flutterCheckBox(), rp->lidsCheckBox()}) {
        cb->setEnabled(!bCompet);
        if (bCompet) {
            cb->setChecked(value == RunMode::Wpx);
        }
    }
    if (bCompet) {
        rp->durationSpin()->setValue(competitionDuration_);
    }

    // Run menu and Run-button popup share these actions.
    for (QAction* a : {menus_->runPileUp, menus_->runSingleCalls, menus_->runWpx,
                       menus_->runHst}) {
        a->setEnabled(bStop);
    }
    menus_->runStop->setEnabled(!bStop);

    menus_->settingsCall->setEnabled(bStop);
    menus_->durationMenu->setEnabled(bStop);
    for (QAction* a : {menus_->settingsQrn, menus_->settingsQrm, menus_->settingsQsb,
                       menus_->settingsFlutter, menus_->settingsLids}) {
        a->setEnabled(!bCompet);
    }

    // HST specifics: Activity fixed at 4, bandwidth at 600 Hz.
    menus_->activityMenu->setEnabled(!hst);
    menus_->cwBandwidthMenu->setEnabled(!hst);
    rp->activitySpin()->setEnabled(!hst);
    if (hst) {
        rp->activitySpin()->setValue(4);
    }
    rp->bandwidthCombo()->setEnabled(!hst);
    if (hst) {
        rp->bandwidthCombo()->setCurrentIndex(10);
    }

    if (hst) {
        bottomPanel_->setScoreTableVisible(false);
    } else if (!bStop) {
        bottomPanel_->setScoreTableVisible(true);
    }

    // Mode caption: red for competitions, green otherwise.
    if (auto* lbl = bottomPanel_->modeLabel(); lbl != nullptr) {
        switch (value) {
            case RunMode::PileUp: lbl->setText(QStringLiteral("Pile-Up"));      break;
            case RunMode::Single: lbl->setText(QStringLiteral("Single Calls")); break;
            case RunMode::Wpx:    lbl->setText(QStringLiteral("COMPETITION"));  break;
            case RunMode::Hst:    lbl->setText(QStringLiteral("H S T"));        break;
            case RunMode::Stop:   lbl->clear();                                 break;
        }
        QPalette pal = lbl->palette();
        pal.setColor(QPalette::WindowText, bCompet ? QColor(Qt::red) : QColor(0, 0x80, 0));
        lbl->setPalette(pal);
    }

    if (!bStop) {
        // Tst.Me.AbortSend; BlockNumber := 0; Me.Nr := 1 (sim side);
        // Log.Clear; WipeBoxes; IncRit(0).
        lastRunMode_ = mode;
        log_.clear();
        if (logView_ != nullptr) {
            logView_->setHeader(hst ? LogView::HeaderStyle::HstScore
                                    : LogView::HeaderStyle::WpxPrefix);
        }
        const QString empty = hst ? QString() : QStringLiteral("0");
        for (int c = 0; c < 2; ++c) {
            if (auto* l = bottomPanel_->scoreCell(0, c)) l->setText(empty);
            if (auto* l = bottomPanel_->scoreCell(1, c)) l->setText(empty);
            if (auto* l = bottomPanel_->scoreCell(2, c)) l->setText(QStringLiteral("0"));
        }
        if (auto* hist = bottomPanel_->histogramPanel()) {
            hist->clear();
        }
        wipeBoxes();
        incRit(0);
    }

    emit runModeRequested(mode);
}

void MainWindow::wireBottomPanelClicks() {
    // F1..F8 push buttons → SendClick (same mapping as the Send menu).
    using mr::sim::Message;
    static constexpr Message kSendMap[8] = {
        Message::Cq,  Message::Nr,  Message::Tu,    Message::MyCall,
        Message::HisCall, Message::B4, Message::Qm, Message::Nil,
    };
    for (int i = 0; i < 8; ++i) {
        if (auto* btn = fKeyButton(i); btn != nullptr) {
            const Message m = kSendMap[i];
            connect(btn, &QPushButton::clicked, this,
                    [this, m]() { sendMsg(static_cast<int>(m)); });
        }
    }
}

void MainWindow::wireCheckBoxSync() {
    // Pascal: the right-panel checkboxes and the Settings menu items
    // are two views of the same on/off state. We bridge them so
    // toggling either one updates the other's check mark (without
    // looping — Qt's setChecked is a no-op when the state matches).
    auto bridge = [this](QCheckBox* cb, QAction* a, auto signalMember) {
        connect(cb, &QCheckBox::toggled, a, &QAction::setChecked);
        connect(a, &QAction::toggled, cb, &QCheckBox::setChecked);
        connect(cb, &QCheckBox::toggled, this, signalMember);
    };
    bridge(rightPanel_->qrnCheckBox(),     menus_->settingsQrn,     &MainWindow::qrnToggled);
    bridge(rightPanel_->qrmCheckBox(),     menus_->settingsQrm,     &MainWindow::qrmToggled);
    bridge(rightPanel_->qsbCheckBox(),     menus_->settingsQsb,     &MainWindow::qsbToggled);
    bridge(rightPanel_->flutterCheckBox(), menus_->settingsFlutter, &MainWindow::flutterToggled);
    bridge(rightPanel_->lidsCheckBox(),    menus_->settingsLids,    &MainWindow::lidsToggled);
    bridge(rightPanel_->qskCheckBox(),     menus_->settingsQsk,     &MainWindow::qskToggled);
}

void MainWindow::wireNumericSettings() {
    // The right-panel controls are the single source of truth. Each
    // drives its *Changed signal; the matching Settings submenu sets
    // the control (so the change flows through that same signal) and
    // mirrors the control's value back as a check mark.
    auto* rp = rightPanel_;

    // Spin-backed settings: WPM (SpinEdit1), Activity (SpinEdit3),
    // Duration (SpinEdit2).
    auto wireSpin = [this](QSpinBox* spin, QMenu* menu,
                           void (MainWindow::*changed)(int)) {
        connect(spin, QOverload<int>::of(&QSpinBox::valueChanged),
                this, changed);
        connect(spin, QOverload<int>::of(&QSpinBox::valueChanged),
                menu, [menu](int v) { checkMatchingAction(menu, v); });
        for (QAction* a : menu->actions()) {
            connect(a, &QAction::triggered, spin,
                    [a, spin]() { spin->setValue(a->data().toInt()); });
        }
        checkMatchingAction(menu, spin->value());
    };
    wireSpin(rp->wpmSpin(),      menus_->cwSpeedMenu,  &MainWindow::wpmChanged);
    wireSpin(rp->activitySpin(), menus_->activityMenu, &MainWindow::activityChanged);
    wireSpin(rp->durationSpin(), menus_->durationMenu, &MainWindow::durationChanged);

    // Combo-backed settings: Pitch (ComboBox1), RX Bandwidth
    // (ComboBox2). Item data carries the bare Hz value.
    auto wireCombo = [this](QComboBox* combo, QMenu* menu,
                            void (MainWindow::*changed)(int)) {
        connect(combo, QOverload<int>::of(&QComboBox::currentIndexChanged),
                this, [this, combo, menu, changed](int /*idx*/) {
                    const int hz = combo->currentData().toInt();
                    checkMatchingAction(menu, hz);
                    emit (this->*changed)(hz);
                });
        for (QAction* a : menu->actions()) {
            connect(a, &QAction::triggered, combo, [a, combo]() {
                if (const int i = combo->findData(a->data()); i >= 0) {
                    combo->setCurrentIndex(i);
                }
            });
        }
        checkMatchingAction(menu, combo->currentData().toInt());
    };
    wireCombo(rp->pitchCombo(),     menus_->cwPitchMenu,     &MainWindow::pitchChanged);
    wireCombo(rp->bandwidthCombo(), menus_->cwBandwidthMenu, &MainWindow::bandwidthChanged);

    // Monitor level (VolumeSlider1). Pascal Mon. Level menu items map
    // discrete dB values; we apply via the slider's setDb() so the
    // visual knob jumps and the slider's own change signal fires. The
    // slider is continuous, so the check mark only appears when it
    // sits on one of the listed steps.
    if (auto* vs = rp->volumeSlider(); vs != nullptr) {
        auto syncMonLevel = [this, vs]() {
            checkMatchingAction(menus_->monLevelMenu,
                                static_cast<int>(std::lround(vs->db())));
        };
        connect(vs, &VolumeSlider::valueChanged,
                this, &MainWindow::monitorLevelChanged);
        connect(vs, &VolumeSlider::valueChanged, this, syncMonLevel);
        for (QAction* a : menus_->monLevelMenu->actions()) {
            connect(a, &QAction::triggered, this, [a, vs]() {
                vs->setDb(static_cast<double>(a->data().toInt()));
            });
        }
        syncMonLevel();
    }

    // MyCall (Edit4). Pascal: ecUpperCase + 12 chars; the RightPanel
    // already enforces those via the validator. Phase E pushes the
    // value through to Sim::Contest on every change.
    connect(rp->callEdit(), &QLineEdit::textChanged,
            this, &MainWindow::myCallsignChanged);

    // RIT slider in the bottom panel.
    if (auto* rs = bottomPanel_->ritSlider(); rs != nullptr) {
        connect(rs, &RitSlider::ritChanged, this, &MainWindow::ritChanged);
    }

    // Pascal Edit1Change: an empty Call box clears NrSent; any edit is
    // offered to the call being keyed (UpdateCallInMessage), and if it
    // can't be applied, CallSent is cleared (onCallEditResult). An empty
    // box can never be applied, so that case is decided here.
    connect(bottomPanel_->callEdit(), &QLineEdit::textChanged, this,
            [this](const QString& text) {
                if (text.isEmpty()) {
                    nrSent_ = false;
                    callSent_ = false;
                    return;
                }
                ++pendingCallEditResults_;
                emit playerCallEdited(text);
            });

    // Pascal CheckBoxClick / CheckBox1Click: back to the Call box.
    for (QCheckBox* cb : {rp->qskCheckBox(), rp->qrnCheckBox(), rp->qrmCheckBox(),
                          rp->qsbCheckBox(), rp->flutterCheckBox(), rp->lidsCheckBox()}) {
        connect(cb, &QCheckBox::clicked, this,
                [this]() { bottomPanel_->callEdit()->setFocus(); });
    }
}

}  // namespace mr::ui
