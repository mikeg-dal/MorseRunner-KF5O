// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal VCL/Crc32.pas port. Standard 256-entry table-driven CRC32.
// Pascal seeds with `$C90C2086` and the function returns the
// post-mix value as an 8-hex-digit string at the end of the WPX
// score submission line.

#pragma once

#include <cstdint>
#include <string_view>

namespace mr::scoring {

[[nodiscard]] std::uint32_t calculateCrc32(std::string_view str,
                                            std::uint32_t seed) noexcept;

}  // namespace mr::scoring
