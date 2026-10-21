// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The Contest is the block renderer the simulation thread drives (C++
// SimulationWorker owns a Contest). Declared here, in the module that
// owns the protocol, so the app needs no @retroactive conformance.

import MRSimulation

extension Contest: BlockRenderer {}
