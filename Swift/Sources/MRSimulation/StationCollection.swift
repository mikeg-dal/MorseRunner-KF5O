// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of StnColl.pas TStations (C++ src/simulation/StationCollection).
// Owns every live audible source (DX callers + QRN/QRM interferers).
// Provides factory methods that mirror the Pascal AddCaller / AddQrn /
// AddQrm helpers and a sweep() pass for removing finished stations.

/// Read-only to the app (it iterates the stations and reads `dxCount`);
/// only the engine adds, sweeps or clears.
public final class StationCollection: RandomAccessCollection {
    private(set) var all: [Station] = []

    init() {}

    public var startIndex: Int { all.startIndex }
    public var endIndex: Int { all.endIndex }
    public subscript(i: Int) -> Station { all[i] }

    // Factories. Pascal: AddCaller / AddQrn / AddQrm.
    @discardableResult
    func addCaller(_ engine: any Engine, _ call: String) -> DxStation {
        let s = DxStation(engine: engine, call: call)
        all.append(s)
        return s
    }

    @discardableResult
    func addQrn(_ engine: any Engine) -> QrnStation {
        let s = QrnStation(engine: engine)
        all.append(s)
        return s
    }

    @discardableResult
    func addQrm(_ engine: any Engine, _ call: String) -> QrmStation {
        let s = QrmStation(engine: engine, call: call)
        all.append(s)
        return s
    }

    /// Removes finished stations: DxStation.shouldRemove, or isFinished
    /// for QRN / QRM. Stable: survivors keep their order (the Contest
    /// ticks last-to-first, so order is observable).
    func sweep() {
        all.removeAll { s in
            if let dx = s as? DxStation { return dx.shouldRemove }
            if let qrn = s as? QrnStation { return qrn.isFinished }
            if let qrm = s as? QrmStation { return qrm.isFinished }
            return false
        }
    }

    func clear() { all.removeAll() }

    /// How many DxStations are alive (not finished)? Pascal:
    /// TContest.DxCount. A Done station still waiting for its QSO to be
    /// logged is not counted.
    public var dxCount: Int {
        var n = 0
        for s in all {
            if let dx = s as? DxStation, !dx.isFinished {
                n += 1
            }
        }
        return n
    }
}
