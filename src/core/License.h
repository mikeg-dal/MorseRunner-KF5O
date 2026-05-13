// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include <QString>

namespace mr::core {

// Single source of truth for the about-dialog license blurb. The full MPL
// text lives in LICENSE at the project root and is shipped in the bundle
// Resources for users who want the canonical document; this short text is
// the human-readable summary that Apple's About dialog can render in a
// small label without a license-text scroller.
[[nodiscard]] inline QString licenseSummary() {
    return QStringLiteral(
        "Morse Runner — macOS Qt 6 port\n"
        "\n"
        "Original Delphi/VCL implementation (c) 2004-2006 Alex Shovkoplyas, VE3NEA.\n"
        "macOS port (c) 2026 Mike Garcia.\n"
        "\n"
        "This program is distributed under the Mozilla Public License v2.0.\n"
        "A copy of the license is included in the application bundle as\n"
        "Resources/LICENSE and is also available at\n"
        "https://mozilla.org/MPL/2.0/.\n");
}

}  // namespace mr::core
