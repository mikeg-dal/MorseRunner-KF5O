// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Ports of tests/simulation/test_is_my_call.cpp, test_messages.cpp and
// test_number_format.cpp.

import MRCore
@testable import MRSimulation
import Testing

private func run(_ mine: String, _ his: String, lids: Bool = false) -> CallMatch {
    isMyCall(IsMyCallOptions(mine: mine, his: his, lidsMode: lids), Random(seed: 42))
}

@Suite struct IsMyCallTests {
    @Test func exactMatchIsYes() {
        #expect(run("VE3NEA", "VE3NEA") == .yes)
        #expect(run("KF5O", "KF5O") == .yes)
    }

    @Test func completelyDifferentIsNo() {
        #expect(run("VE3NEA", "JA1XYZ") == .no)
        #expect(run("KF5O", "G0ABC") == .no)
    }

    @Test func oneTypoIsAlmost() {
        #expect(run("VE3NEA", "VE3MEA") == .almost)
    }

    @Test func wildcardDowngradesYesToAlmost() {
        #expect(run("VE3NEA", "VE3?EA") == .almost)
    }

    @Test func partialTrailingIsAlmost() {
        #expect(run("K1ABC", "K1A") == .almost)
    }

    @Test func shortHeardCallWithTypoIsNoWithoutLids() {
        #expect(run("VE3NEA", "VX", lids: false) == .no)
    }

    @Test func cleanShortPrefixIsAlmost() {
        #expect(run("VE3NEA", "VE", lids: false) == .almost)
    }

    @Test func tooFewNonWildcardsIsNo() {
        #expect(run("VE3NEA", "?") == .no)
        #expect(run("VE3NEA", "V?") == .no)
        #expect(run("VE3NEA", "") == .no)
    }

    @Test func lidsMishearingHappensSometimes() {
        var yes = 0
        var almost = 0
        let trials = 1000
        for i in 0..<trials {
            let r = isMyCall(IsMyCallOptions(mine: "VE3NEA", his: "VE3NEA", lidsMode: true),
                             Random(seed: UInt64(0xC0FFEE + i)))
            if r == .yes { yes += 1 } else if r == .almost { almost += 1 }
        }
        #expect(yes * 100 > trials * 95)
        #expect(almost * 100 < trials * 5)
    }
}

@Suite struct MessagesTests {
    @Test func enumCountMatchesTableSize() {
        #expect(Message.allCases.count == 23)
    }

    @Test func cqTemplateExact() {
        #expect(Message.cq.template == "CQ <my> TEST")
    }

    @Test func longCqTemplateExact() {
        #expect(Message.longCq.template == "CQ CQ TEST <my> <my> TEST")
    }

    @Test func allNonGarbageNonNoneHaveTemplates() {
        for m in Message.allCases {
            if m == .none || m == .garbage {
                #expect(m.template.isEmpty, "\(m.name)")
            } else {
                #expect(!m.template.isEmpty, "\(m.name)")
            }
        }
    }

    @Test func qsyHasDoubleSpace() {
        #expect(Message.qsy.template == "<his>  QSY QSY")
    }

    @Test func rNr2HasTwoNumberSlots() {
        #expect(Message.rNr2.template == "R <#> <#>")
    }

    @Test func messageSetContains() {
        var s = MessageSet.of(.cq)
        s |= MessageSet.of(.tu)
        #expect(s.contains(.cq))
        #expect(s.contains(.tu))
        #expect(!s.contains(.b4))
        #expect(!s.contains(.none))
        #expect(MessageSet.of(.none).isEmpty)
    }

    @Test func messageSetBitLayoutMatchesBitset() {
        // bit i = Message raw value i (std::bitset::to_ullong()).
        #expect(MessageSet([.cq]).rawValue == 2)
        #expect(MessageSet([.nr, .hisCall]).rawValue == (1 << 2) | (1 << 5))
        var n = MessageSet()
        n.insert(.none)  // the DxStation timeout path sets bit 0
        #expect(n.rawValue == 1 && n.count == 1 && !n.contains(.none))
    }

    @Test func names() {
        #expect(Message.none.name == "None")
        #expect(Message.rNr2.name == "R_Nr2")
        #expect(Message.agn.name == "Agn")
    }
}

@Suite struct NrAsTextTests {
    @Test func hstModeNoCutNumbers() {
        // In HST mode the cut-number substitutions are suppressed; RST=599
        // still collapses to 5NN.
        let opts = NrFormatOptions(rst: 599, nr: 100, hstMode: true, lidError: false)
        #expect(nrAsText(opts, Random(seed: 1)) == "5NN100")
    }

    @Test func rstNineNineNineCollapses() {
        let opts = NrFormatOptions(rst: 599, nr: 1, hstMode: true, lidError: false)
        #expect(nrAsText(opts, Random(seed: 2)) == "5NN001")
    }

    @Test func zeroSubstitutionUsesOOrTConsistently() {
        for seed in 0..<50 {
            let opts = NrFormatOptions(rst: 599, nr: 100, hstMode: false, lidError: false)
            let s = nrAsText(opts, Random(seed: UInt64(seed)))
            let hasO = s.contains("O")
            let hasT = s.contains("T")
            #expect(hasO || hasT || s.contains("0"))
            if hasO {
                #expect(!s.contains("0"))
            }
        }
    }

    @Test func nineSubstitutedAsN() {
        let opts = NrFormatOptions(rst: 599, nr: 9, hstMode: false, lidError: false)
        var nCount = 0
        let trials = 2000
        for i in 0..<trials {
            let s = nrAsText(opts, Random(seed: UInt64(0xBEEF + i)))
            // The NR portion starts at offset 3 (after "5NN").
            if s.dropFirst(3).contains("N") {
                nCount += 1
            }
        }
        #expect(nCount * 100 > trials * 90)
        #expect(nCount * 100 < trials * 100)
    }

    @Test func lidErrorAppendsEEEEECorrection() {
        let opts = NrFormatOptions(rst: 599, nr: 234, hstMode: true, lidError: true)
        let s = nrAsText(opts, Random(seed: 11))
        #expect(s.contains("EEEEE 234"))
    }
}
