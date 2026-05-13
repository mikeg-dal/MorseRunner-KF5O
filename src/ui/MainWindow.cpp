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

#include <QCheckBox>
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
#include <QVBoxLayout>

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
    menus_->runPileUp->setShortcut(QKeySequence(Qt::Key_F8));
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

void MainWindow::onClockTicked(int seconds) {
    // hh:mm:ss formatter mirroring the Pascal panel readout.
    sessionSeconds_ = seconds;
    const int h = seconds / 3600;
    const int m = (seconds / 60) % 60;
    const int s = seconds % 60;
    const QString text = QStringLiteral("%1:%2:%3")
        .arg(h, 2, 10, QChar('0'))
        .arg(m, 2, 10, QChar('0'))
        .arg(s, 2, 10, QChar('0'));
    if (auto* lbl = bottomPanel_->clockLabel(); lbl != nullptr) {
        lbl->setText(text);
    }
    // Live rate readout. Pascal ShowRate computes
    // "QSOs * 3600 / SessionSeconds" then writes "%d  qso/hr.".
    if (auto* rate = bottomPanel_->rateLabel(); rate != nullptr) {
        const int qsoPerHr = (sessionSeconds_ > 0)
            ? (totalLoggedQsos_ * 3600 / sessionSeconds_)
            : 0;
        rate->setText(QStringLiteral("%1  qso/hr.").arg(qsoPerHr));
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

void MainWindow::appendScoreHistoryLine(const QString& line) const {
    const QString path = scoreHistoryPath();
    QFileInfo info(path);
    QDir().mkpath(info.absolutePath());
    QFile f(path);
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        f.write(line.toUtf8());
        f.write("\n");
    }
}

void MainWindow::onContestEnded(int mode) {
    // Phase F: the WPX-flavoured submission ScoreDialog. Pascal
    // Main.PopupScoreWpx builds:
    //   "YYYY-MM-DD <call> <pts> <mult> [<CRC32>]"
    // where the CRC32 seed is 0xC90C2086 and the inner string ends
    // with a trailing space (matches Pascal's Format directive).
    using mr::sim::RunMode;
    const auto runMode = static_cast<RunMode>(mode);

    // Read MyCall from the right-panel edit so we don't need a sim
    // round-trip to know what the user just submitted as.
    QString myCall;
    if (auto* rp = rightPanel_; rp != nullptr && rp->callEdit() != nullptr) {
        myCall = rp->callEdit()->text();
    }

    const QString dateStr =
        QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"));

    // Pascal Main.PopupScoreWpx fires for every non-HST mode. HST
    // gets the bare Score message box (PopupScoreHst). Single Calls
    // scores by Pts × Mul same as Pile-Up / WPX, so it joins the
    // submission-string dialog.
    if (runMode != RunMode::Hst) {
        const QString inner = QStringLiteral("%1 %2 %3 %4 ")
            .arg(dateStr, myCall,
                 QString::number(scoreVerified_),
                 QString::number(verifiedPrefixes_.size()));
        const std::uint32_t crc = mr::scoring::calculateCrc32(
            inner.toStdString(),
            static_cast<std::uint32_t>(0xC90C2086U));
        const QString stamped = inner + QStringLiteral("[%1]")
            .arg(crc, 8, 16, QChar('0')).toUpper();

        // Persist the submission line to the per-user history file so
        // File → View Score Table can show past sessions.
        appendScoreHistoryLine(stamped);

        mr::persistence::Settings settings;
        const int prevHi = settings.hiScore();
        const int finalScore = scoreVerified_
                               * static_cast<int>(verifiedPrefixes_.size());
        const bool newHi = (finalScore > prevHi);
        if (newHi) {
            settings.setHiScore(finalScore);
        }

        ScoreDialog dlg(stamped, newHi, this);
        dlg.exec();
    } else {
        // HST / Single / other modes: simpler readout — Pascal's
        // PopupScoreHst just shows the score in a plain message box.
        QMessageBox::information(this,
            QStringLiteral("Contest finished"),
            QStringLiteral("Score: %1").arg(scoreVerified_));
    }
}

// (Previously housed `extractPrefixSimple` here. Replaced by the full
// Pascal-faithful `mr::scoring::extractPrefix` — see
// `src/scoring/ExtractPrefix.h`.)

void MainWindow::onDxQsoCompleted(const QString& call, int rst, int nr,
                                  float /*minute*/) {
    // Sim thread is telling us a DX station reached Done. Store the
    // truth keyed by uppercase call so the next Enter press can
    // validate against it.
    truthByCall_.insert(call.toUpper(), DxTruth{rst, nr});
}

namespace {

void setScoreCell(QLabel* lbl, int v) {
    if (lbl != nullptr) {
        lbl->setText(QString::number(v));
    }
}

}  // namespace

void MainWindow::keyPressEvent(QKeyEvent* event) {
    // Pascal Main.pas FormKeyDown bindings. Function keys land on the
    // QAction shortcuts already; here we handle the rest.
    const auto key = event->key();
    const auto mods = event->modifiers();

    // Space: focus round-robin through Call → RST → Nr → Call.
    if (key == Qt::Key_Space && mods == Qt::NoModifier
        && bottomPanel_ != nullptr) {
        QLineEdit* edits[3] = {
            bottomPanel_->callEdit(),
            bottomPanel_->rstEdit(),
            bottomPanel_->nrEdit()};
        QWidget* fw = focusWidget();
        int next = 0;
        for (int i = 0; i < 3; ++i) {
            if (edits[i] == fw) {
                next = (i + 1) % 3;
                break;
            }
        }
        if (edits[next] != nullptr) {
            edits[next]->setFocus();
        }
        event->accept();
        return;
    }

    // Esc: abort the player's transmission.
    if (key == Qt::Key_Escape && mods == Qt::NoModifier) {
        emit abortSendRequested();
        event->accept();
        return;
    }

    // F11 / Ctrl-W / Alt-W: wipe entry fields.
    if ((key == Qt::Key_F11 && mods == Qt::NoModifier)
        || (key == Qt::Key_W && (mods == Qt::ControlModifier
                                 || mods == Qt::AltModifier))) {
        if (bottomPanel_ != nullptr) {
            if (auto* c = bottomPanel_->callEdit()) c->clear();
            if (auto* r = bottomPanel_->rstEdit())  r->clear();
            if (auto* n = bottomPanel_->nrEdit())   n->clear();
            if (auto* c = bottomPanel_->callEdit()) c->setFocus();
        }
        event->accept();
        return;
    }

    // Up / Down: RIT ±50 Hz.
    if ((key == Qt::Key_Up || key == Qt::Key_Down)
        && mods == Qt::NoModifier && bottomPanel_ != nullptr) {
        if (auto* rs = bottomPanel_->ritSlider(); rs != nullptr) {
            const int delta = (key == Qt::Key_Up) ? 50 : -50;
            rs->setRitHz(rs->ritHz() + delta);
        }
        event->accept();
        return;
    }

    // `.`, `+`, `[`: send F3 (TU) and immediately save the QSO. Pascal
    // combines the TU send and the SaveQso into one keystroke as the
    // common close-the-QSO shortcut.
    if (mods == Qt::NoModifier
        && (key == Qt::Key_Period
            || key == Qt::Key_Plus
            || key == Qt::Key_BracketLeft)) {
        emit sendMessageRequested(static_cast<int>(mr::sim::Message::Tu));
        onSaveQsoRequested();
        event->accept();
        return;
    }

    QMainWindow::keyPressEvent(event);
}

void MainWindow::onSaveQsoRequested() {
    // E.G4 minimum-viable QSO logging. The Pascal Log.pas pipeline
    // does call-vs-truth validation against the DxStation that just
    // finished — we don't have CompletedQso back-fill plumbed end-to-end
    // yet, so this writes the player's entered values with an empty
    // error tag. Phase F replaces the placeholder tag with the
    // checked-and-scored result.
    if (bottomPanel_ == nullptr || logView_ == nullptr) {
        return;
    }
    auto* call = bottomPanel_->callEdit();
    auto* rst  = bottomPanel_->rstEdit();
    auto* nr   = bottomPanel_->nrEdit();
    if (call == nullptr || rst == nullptr || nr == nullptr) {
        return;
    }
    const QString callText = call->text().trimmed();
    if (callText.isEmpty()) {
        return;
    }

    // Pascal Log.pas::LastQsoToScreen row format:
    //   ' hh:nn:ss  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s'
    // Column order is Recv (rcvdRst rcvdNr) then Sent (player hard-codes
    // 599 0001 until the scoring engine is in). Received RST/NR come
    // from the entry fields.
    const QTime now = QTime::currentTime();
    const QString timeStr = now.toString(QStringLiteral("HH:mm:ss"));
    const int rcvdRst = rst->text().toInt();
    const int rcvdNr  = nr->text().toInt();
    // Pascal WPX uses ExtractPrefix for the multiplier column;
    // HST repurposes the Pref column to show the per-QSO CallToScore
    // value (the WPX multiplier doesn't apply to HST). The full
    // Pascal-faithful ExtractPrefix lives in scoring/ExtractPrefix.h.
    const bool isHst =
        currentRunMode_ == static_cast<int>(mr::sim::RunMode::Hst);
    const QString wpxPrefix = QString::fromStdString(
        mr::scoring::extractPrefix(callText.toStdString()));
    const int callPts = mr::scoring::callToScore(callText.toStdString());
    const QString displayPref = isHst
        ? QString::number(callPts)
        : wpxPrefix;

    // Chk-column validation. Pascal CheckErr writes:
    //   DUP — call already logged this session
    //   NIL — no DX with this call has completed (we never heard it)
    //   RST — call/NR matched but RST differed
    //   NR  — call/RST matched but NR differed
    //   "   " — clean (verified)
    const QString upperCall = callText.toUpper();
    QString tag = QStringLiteral("   ");
    bool verified = false;
    if (loggedCalls_.contains(upperCall)) {
        tag = QStringLiteral("DUP");
    } else if (!truthByCall_.contains(upperCall)) {
        tag = QStringLiteral("NIL");
    } else {
        const auto truth = truthByCall_.value(upperCall);
        const bool rstOk = (rcvdRst == truth.rst);
        const bool nrOk  = (rcvdNr  == truth.nr);
        if (rstOk && nrOk) {
            verified = true;          // clean — counts toward Verified score
        } else if (!rstOk && nrOk) {
            tag = QStringLiteral("RST");
        } else if (rstOk && !nrOk) {
            tag = QStringLiteral("NR ");
        } else {
            tag = QStringLiteral("NR ");
        }
    }

    const QString row = QStringLiteral(" %1  %2  %3 %4  599 0001  %5  ")
        .arg(timeStr)
        .arg(callText, -12)
        .arg(rcvdRst, 3, 10, QChar('0'))
        .arg(rcvdNr, 4, 10, QChar('0'))
        .arg(displayPref, -5);
    logView_->appendQsoRow(row, tag);

    // Mode-aware scoring (Pascal Log.pas UpdateStats vs UpdateStatsHst).
    //
    //   WPX (Pile-Up, Single, Wpx)  →  Pts = QSO count
    //                                  Mul = unique-prefix count
    //                                  Score = Pts × Mul
    //   HST                          →  Pts = sum of CallToScore
    //                                  Mul = blank/0
    //                                  Score = Pts (no multiplier)
    //
    // Both columns (Raw / Verified) follow the same rule; Verified
    // counts only QSOs with a clean Chk tag.
    if (tag != QStringLiteral("DUP")) {
        loggedCalls_.insert(upperCall);
        if (isHst) {
            scoreRaw_ += callPts;
        } else {
            ++scoreRaw_;
            if (!wpxPrefix.isEmpty()) {
                rawPrefixes_.insert(wpxPrefix);
            }
        }
        if (verified) {
            ++verifiedQsos_;
            if (isHst) {
                scoreVerified_ += callPts;
            } else {
                ++scoreVerified_;
                if (!wpxPrefix.isEmpty()) {
                    verifiedPrefixes_.insert(wpxPrefix);
                }
            }
        }
    }
    if (isHst) {
        // Pascal: Items[0].SubItems := ''; Items[1].SubItems := '';
        // Items[2] = Score. We show the raw/verified Pts (sum of
        // CallToScore) on the Score row directly.
        setScoreCell(bottomPanel_->scoreCell(0, 0), 0);
        setScoreCell(bottomPanel_->scoreCell(0, 1), 0);
        setScoreCell(bottomPanel_->scoreCell(1, 0), 0);
        setScoreCell(bottomPanel_->scoreCell(1, 1), 0);
        setScoreCell(bottomPanel_->scoreCell(2, 0), scoreRaw_);
        setScoreCell(bottomPanel_->scoreCell(2, 1), scoreVerified_);
    } else {
        const int rawMult = static_cast<int>(rawPrefixes_.size());
        const int verMult = static_cast<int>(verifiedPrefixes_.size());
        setScoreCell(bottomPanel_->scoreCell(0, 0), scoreRaw_);
        setScoreCell(bottomPanel_->scoreCell(0, 1), scoreVerified_);
        setScoreCell(bottomPanel_->scoreCell(1, 0), rawMult);
        setScoreCell(bottomPanel_->scoreCell(1, 1), verMult);
        setScoreCell(bottomPanel_->scoreCell(2, 0), scoreRaw_ * rawMult);
        setScoreCell(bottomPanel_->scoreCell(2, 1), scoreVerified_ * verMult);
    }

    // Histogram bin: each bin covers kHistogramBinMinutes (5 by
    // default). Pascal Histo[i] is bumped from PaintHisto when a QSO
    // is logged within the corresponding minute window.
    ++totalLoggedQsos_;
    if (auto* hist = bottomPanel_->histogramPanel(); hist != nullptr) {
        using namespace mr::constants::Ui;
        const int minute = sessionSeconds_ / 60;
        const int bin = std::clamp(minute / kHistogramBinMinutes,
                                   0, kHistogramBins - 1);
        ++histogramBins_[static_cast<std::size_t>(bin)];
        hist->setBinCount(bin, histogramBins_[static_cast<std::size_t>(bin)]);
    }

    call->clear();
    rst->clear();
    nr->clear();
    call->setFocus();
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

    // Run-mode menu items → runModeRequested + enable/disable Stop.
    // Pascal: Stop starts disabled at startup; selecting any run mode
    // enables it, and Stop disables itself when clicked.
    auto enterRunMode = [this](int mode) {
        // Cache the just-selected mode so onSaveQsoRequested can
        // branch Pascal-style scoring (HST = CallToScore sum; others
        // = QSO count × prefix multiplier) without a sim round-trip.
        currentRunMode_ = mode;
        // Pascal Main.pas: starting a Run clears the prior session's
        // counters so the new contest begins from zero. The log pane
        // is preserved across Stop (per parity) but reset here on a
        // fresh start. Stop itself leaves the score visible so the
        // user can read their final tally — opposite of where we had
        // the reset before.
        sessionSeconds_ = 0;
        totalLoggedQsos_ = 0;
        verifiedQsos_ = 0;
        scoreRaw_ = 0;
        scoreVerified_ = 0;
        rawPrefixes_.clear();
        verifiedPrefixes_.clear();
        loggedCalls_.clear();
        truthByCall_.clear();
        histogramBins_.fill(0);
        for (int r = 0; r < 3; ++r) {
            for (int c = 0; c < 2; ++c) {
                if (auto* lbl = bottomPanel_->scoreCell(r, c)) {
                    lbl->setText(QStringLiteral("0"));
                }
            }
        }
        if (auto* rate = bottomPanel_->rateLabel()) {
            rate->setText(QStringLiteral("0  qso/hr."));
        }
        if (auto* clk = bottomPanel_->clockLabel()) {
            clk->setText(QStringLiteral("00:00:00"));
        }
        if (auto* hist = bottomPanel_->histogramPanel()) {
            hist->clear();
        }
        if (auto* lv = logView_) {
            lv->clear();
        }
        emit runModeRequested(mode);
        menus_->runStop->setEnabled(true);
    };
    connect(menus_->runPileUp,      &QAction::triggered, this,
            [enterRunMode]() { enterRunMode(static_cast<int>(RunMode::PileUp)); });
    connect(menus_->runSingleCalls, &QAction::triggered, this,
            [enterRunMode]() { enterRunMode(static_cast<int>(RunMode::Single)); });
    connect(menus_->runWpx,         &QAction::triggered, this,
            [enterRunMode]() { enterRunMode(static_cast<int>(RunMode::Wpx)); });
    connect(menus_->runHst,         &QAction::triggered, this,
            [enterRunMode]() { enterRunMode(static_cast<int>(RunMode::Hst)); });
    connect(menus_->runStop,        &QAction::triggered, this,
            [this]() {
                // Pascal parity: Stop preserves the score / histogram /
                // clock / log so the user can review the just-finished
                // session. Counters reset only when a new Run starts.
                emit runModeRequested(static_cast<int>(RunMode::Stop));
                menus_->runStop->setEnabled(false);
            });

    // Send menu (each F-key) → sendMessageRequested
    static constexpr Message kSendMap[8] = {
        Message::Cq,  Message::Nr,  Message::Tu,    Message::MyCall,
        Message::HisCall, Message::B4, Message::Qm, Message::Nil,
    };
    for (int i = 0; i < 8; ++i) {
        if (auto* a = sendAction(i); a != nullptr) {
            const Message m = kSendMap[i];
            connect(a, &QAction::triggered, this,
                    [this, m]() { emit sendMessageRequested(static_cast<int>(m)); });
        }
    }

    // Settings → toggled signals
    connect(menus_->settingsQrn,     &QAction::toggled, this, &MainWindow::qrnToggled);
    connect(menus_->settingsQrm,     &QAction::toggled, this, &MainWindow::qrmToggled);
    connect(menus_->settingsQsb,     &QAction::toggled, this, &MainWindow::qsbToggled);
    connect(menus_->settingsFlutter, &QAction::toggled, this, &MainWindow::flutterToggled);
    connect(menus_->settingsLids,    &QAction::toggled, this, &MainWindow::lidsToggled);
    connect(menus_->settingsQsk,     &QAction::toggled, this, &MainWindow::qskToggled);
}

void MainWindow::wireBottomPanelClicks() {
    // F1..F8 push buttons in BottomPanel emit clicked() with the same
    // Sim::Message mapping as the Send menu items.
    using mr::sim::Message;
    static constexpr Message kSendMap[8] = {
        Message::Cq,  Message::Nr,  Message::Tu,    Message::MyCall,
        Message::HisCall, Message::B4, Message::Qm, Message::Nil,
    };
    for (int i = 0; i < 8; ++i) {
        if (auto* btn = fKeyButton(i); btn != nullptr) {
            const Message m = kSendMap[i];
            connect(btn, &QPushButton::clicked, this,
                    [this, m]() { emit sendMessageRequested(static_cast<int>(m)); });
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
    // Right-panel SpinBoxes drive the wpmChanged / activityChanged /
    // durationChanged signals; the matching Settings submenu items
    // also emit the same signal and update the spin so the two views
    // stay in sync. Pitch + Bandwidth go through QComboBox::activated
    // (sends the data-payload Hz value).
    auto* rp = rightPanel_;

    // WPM (SpinEdit1 + Settings > CW Speed)
    connect(rp->wpmSpin(),
            QOverload<int>::of(&QSpinBox::valueChanged),
            this, &MainWindow::wpmChanged);
    for (QAction* a : menus_->cwSpeedMenu->actions()) {
        connect(a, &QAction::triggered, this, [this, a, rp]() {
            const int wpm = a->data().toInt();
            QSignalBlocker b(rp->wpmSpin());
            rp->wpmSpin()->setValue(wpm);
            emit wpmChanged(wpm);
        });
    }

    // Pitch (ComboBox1 + Settings > CW Pitch)
    connect(rp->pitchCombo(),
            QOverload<int>::of(&QComboBox::currentIndexChanged),
            this, [this, rp](int /*idx*/) {
                emit pitchChanged(rp->pitchCombo()->currentData().toInt());
            });
    for (QAction* a : menus_->cwPitchMenu->actions()) {
        connect(a, &QAction::triggered, this, [this, a, rp]() {
            const int hz = a->data().toInt();
            const int idx = rp->pitchCombo()->findData(hz);
            QSignalBlocker b(rp->pitchCombo());
            if (idx >= 0) {
                rp->pitchCombo()->setCurrentIndex(idx);
            }
            emit pitchChanged(hz);
        });
    }

    // Bandwidth (ComboBox2 + Settings > CW Bandwidth)
    connect(rp->bandwidthCombo(),
            QOverload<int>::of(&QComboBox::currentIndexChanged),
            this, [this, rp](int /*idx*/) {
                emit bandwidthChanged(rp->bandwidthCombo()->currentData().toInt());
            });
    for (QAction* a : menus_->cwBandwidthMenu->actions()) {
        connect(a, &QAction::triggered, this, [this, a, rp]() {
            const int hz = a->data().toInt();
            const int idx = rp->bandwidthCombo()->findData(hz);
            QSignalBlocker b(rp->bandwidthCombo());
            if (idx >= 0) {
                rp->bandwidthCombo()->setCurrentIndex(idx);
            }
            emit bandwidthChanged(hz);
        });
    }

    // Activity (SpinEdit3 + Settings > Activity)
    connect(rp->activitySpin(),
            QOverload<int>::of(&QSpinBox::valueChanged),
            this, &MainWindow::activityChanged);
    for (QAction* a : menus_->activityMenu->actions()) {
        connect(a, &QAction::triggered, this, [this, a, rp]() {
            const int v = a->data().toInt();
            QSignalBlocker b(rp->activitySpin());
            rp->activitySpin()->setValue(v);
            emit activityChanged(v);
        });
    }

    // Duration (SpinEdit2 + Settings > Duration)
    connect(rp->durationSpin(),
            QOverload<int>::of(&QSpinBox::valueChanged),
            this, &MainWindow::durationChanged);
    for (QAction* a : menus_->durationMenu->actions()) {
        connect(a, &QAction::triggered, this, [this, a, rp]() {
            const int v = a->data().toInt();
            QSignalBlocker b(rp->durationSpin());
            rp->durationSpin()->setValue(v);
            emit durationChanged(v);
        });
    }

    // Monitor level (VolumeSlider1). Pascal Mon. Level menu items map
    // discrete dB values; we apply via the slider's setDb() so the
    // visual knob jumps and the slider's own change signal fires.
    if (auto* vs = rp->volumeSlider(); vs != nullptr) {
        connect(vs, &VolumeSlider::valueChanged,
                this, &MainWindow::monitorLevelChanged);
        for (QAction* a : menus_->monLevelMenu->actions()) {
            connect(a, &QAction::triggered, this, [a, vs]() {
                vs->setDb(static_cast<double>(a->data().toInt()));
            });
        }
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

    // Bottom-panel "Call" edit — the call the player believes the DX
    // is sending. F5 (HisCall) reads this; pre-Phase-E.G4 we wire it
    // here so F5 sends something audible as soon as the user types.
    connect(bottomPanel_->callEdit(), &QLineEdit::textChanged,
            this, &MainWindow::heardCallsignChanged);

    // E.G4: Enter on any of the bottom-panel entry fields commits the
    // QSO to the log pane and clears the row.
    connect(bottomPanel_->callEdit(), &QLineEdit::returnPressed,
            this, &MainWindow::onSaveQsoRequested);
    connect(bottomPanel_->rstEdit(),  &QLineEdit::returnPressed,
            this, &MainWindow::onSaveQsoRequested);
    connect(bottomPanel_->nrEdit(),   &QLineEdit::returnPressed,
            this, &MainWindow::onSaveQsoRequested);
}

}  // namespace mr::ui
