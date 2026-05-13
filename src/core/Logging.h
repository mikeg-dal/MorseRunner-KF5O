// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include <QLoggingCategory>

// Category-based logging lets us silence chatty threads (e.g. mr.audio)
// during a UI debug session without losing simulation visibility, by
// setting QT_LOGGING_RULES=mr.audio.debug=false at launch.
Q_DECLARE_LOGGING_CATEGORY(mrAudio)
Q_DECLARE_LOGGING_CATEGORY(mrSim)
Q_DECLARE_LOGGING_CATEGORY(mrUi)
Q_DECLARE_LOGGING_CATEGORY(mrIo)
Q_DECLARE_LOGGING_CATEGORY(mrDsp)
