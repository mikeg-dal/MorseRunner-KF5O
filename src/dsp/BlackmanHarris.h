// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/MorseKey.pas's `BlackmanHarrisStepResponse` and the
// supporting `BlackmanHarrisKernel`. The Morse keyer uses these to shape
// the on/off transition of each dot and dash — a hard square would
// produce audible "key clicks", a Blackman-Harris-shaped ramp puts the
// sideband energy well below the receiver bandwidth.

#pragma once

#include <vector>

namespace mr::dsp {

// Returns a length-`len` vector that monotonically rises from 0 to 1,
// shaped as the integral of a 4-term Blackman-Harris window. Used as the
// "ramp on" curve; the keyer reverses it for "ramp off".
//
// The output is normalized so the final sample equals exactly 1.0f (so
// the dot/dash sustain section that follows continues at full amplitude
// without a discontinuity).
[[nodiscard]] std::vector<float> blackmanHarrisStep(int len);

}  // namespace mr::dsp
