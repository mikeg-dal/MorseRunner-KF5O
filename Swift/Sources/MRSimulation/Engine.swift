// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Minimal abstract interface that the Station hierarchy and DxOperator
// consult for shared simulation state (C++ src/simulation/Engine.h). The
// original Delphi implementation reaches into the global `Tst`
// (TContest singleton) from anywhere — convenient but untestable. We
// replace that with a reference to this protocol, injected at station
// construction. Contest is the real implementation; the unit tests use
// a small fake.
//
// Internal: only the engine's own types (and tests, via @testable)
// talk to it. Keeping it out of the public surface also keeps the app
// from drawing on the shared Random by accident, which would change
// the simulation.

import MRCore

public enum RunMode: Int, Sendable {
    case stop = 0, pileUp, single, wpx, hst
}

protocol Engine: AnyObject {
    // Time/pacing.
    var currentBlockIndex: Int { get }
    var currentMinute: Float { get }

    // What the player station is doing.
    var myCallsign: String { get }
    /// The callsign the player most recently keyed (Pascal Tst.Me.HisCall).
    /// DX stations compare against what was *sent*, not what is currently
    /// typed in the Call field.
    var heardCallsign: String { get }
    /// Pascal `Tst.Me.State = stSending`. Default false.
    var playerSending: Bool { get }
    /// Pascal Ini.CallsFromKeyer (INI-only): an external keyer sends the
    /// call, so MyStation keys a blank in its place (not in WPX / HST).
    /// Default false.
    var callsFromKeyer: Bool { get }

    /// Pascal TContest.OnMeStartedSending / OnMeFinishedSending. MyStation
    /// calls these synchronously, exactly where Pascal does, so stations
    /// see the player's transmission edges without block-boundary skew.
    /// Default no-ops.
    func onPlayerStartedSending()
    func onPlayerFinishedSending()

    /// The message set the player station most recently sent. DxOperator
    /// inspects this to decide how to respond.
    var myLastMessage: MessageSet { get }

    // Run-mode dispatch.
    var runMode: RunMode { get }

    // Global feature toggles, mirrored from the Ini layer.
    var lidsEnabled: Bool { get }
    var flutterEnabled: Bool { get }
    var qsbEnabled: Bool { get }

    // Settings used by station construction.
    var targetWpm: Int { get }
    var activity: Int { get }
    var bufferSize: Int { get }

    /// Shared random number source. Stations and the FSM all draw from
    /// the same instance so reseeding deterministically reproduces runs.
    var random: Random { get }
}

extension Engine {
    var playerSending: Bool { false }
    var callsFromKeyer: Bool { false }
    func onPlayerStartedSending() {}
    func onPlayerFinishedSending() {}
}
