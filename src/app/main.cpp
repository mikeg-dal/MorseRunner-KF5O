// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Application entry point. Creates the QApplication, applies the global
// theme, hands control to AppController, and runs the event loop.
// AppController owns every other long-lived object (MainWindow today;
// SimulationWorker, AudioEngine, WavWriterThread, CallsignDbLoader in
// subsequent phases).

#include "app/AppController.h"
#include "core/Logging.h"
#include "core/Theme.h"

#include <QApplication>
#include <QObject>

namespace {

void applyThemeStylesheet() {
    auto& theme = mr::core::Theme::instance();
    if (auto* app = qApp; app != nullptr) {
        app->setStyleSheet(theme.stylesheet());
        // Live-update when System Adaptive flips between light and dark.
        QObject::connect(&theme, &mr::core::Theme::themeChanged, app, [&theme]() {
            if (auto* a = qApp; a != nullptr) {
                a->setStyleSheet(theme.stylesheet());
            }
        });
    }
}

}  // namespace

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("MorseRunner"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("morserunner.local"));
    QCoreApplication::setApplicationName(QStringLiteral("Morse Runner"));
    QCoreApplication::setApplicationVersion(QStringLiteral("1.68.0"));

    qInfo(mrUi) << "Morse Runner starting up";

    applyThemeStylesheet();

    mr::app::AppController controller;
    controller.start();

    return QApplication::exec();
}
