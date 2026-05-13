// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "core/Logging.h"

// Default-on for all categories. Production overrides come from
// QT_LOGGING_RULES (e.g. "mr.audio.debug=false") at launch.
Q_LOGGING_CATEGORY(mrAudio, "mr.audio")
Q_LOGGING_CATEGORY(mrSim, "mr.sim")
Q_LOGGING_CATEGORY(mrUi, "mr.ui")
Q_LOGGING_CATEGORY(mrIo, "mr.io")
Q_LOGGING_CATEGORY(mrDsp, "mr.dsp")
