// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Minimal "About Morse Runner" dialog for the Help menu. Renders the
// MPL license summary from Core::licenseSummary() plus the original
// VE3NEA copyright. Phase E will potentially add the version banner
// and a "check for updates" affordance.

#pragma once

#include <QDialog>

namespace mr::ui {

class AboutDialog : public QDialog {
    Q_OBJECT
public:
    explicit AboutDialog(QWidget* parent = nullptr);
};

}  // namespace mr::ui
