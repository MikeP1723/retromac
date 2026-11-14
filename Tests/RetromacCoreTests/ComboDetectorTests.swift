// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let sleepPress: PadButtons = [.l1, .r1, .start]
let exitPress: PadButtons = [.l1, .r1, .select]

@Test func firesAfterTwoSecondHold() {
    var d = ComboDetector()
    #expect(d.update(pad: 0, buttons: sleepPress, at: 0) == nil)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 1.9) == nil)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 2.0) == .sleep)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 3.0) == nil)
}
@Test func releaseThenHoldAgainFiresAgain() {
    var d = ComboDetector()
    _ = d.update(pad: 0, buttons: sleepPress, at: 0)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 2.0) == .sleep)
    _ = d.update(pad: 0, buttons: [.l1], at: 2.5)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 3.0) == nil)
    _ = d.update(pad: 0, buttons: [], at: 3.5)
    _ = d.update(pad: 0, buttons: sleepPress, at: 4.0)
    #expect(d.update(pad: 0, buttons: sleepPress, at: 6.0) == .sleep)
}
@Test func homeVariant() {
    var d = ComboDetector()
    _ = d.update(pad: 0, buttons: [.home, .select], at: 0)
    #expect(d.update(pad: 0, buttons: [.home, .select], at: 2.0) == .exit)
}
@Test func splitAcrossPadsNeverFires() {
    var d = ComboDetector()
    for t in stride(from: 0.0, through: 3.0, by: 0.5) {
        #expect(d.update(pad: 0, buttons: [.l1, .r1], at: t) == nil)
        #expect(d.update(pad: 1, buttons: [.start], at: t) == nil)
    }
}
@Test func disconnectMidHoldResets() {
    var d = ComboDetector()
    _ = d.update(pad: 0, buttons: exitPress, at: 0)
    _ = d.update(pad: 0, buttons: exitPress, at: 1.5)
    d.disconnected(pad: 0)
    _ = d.update(pad: 0, buttons: exitPress, at: 1.6)
    #expect(d.update(pad: 0, buttons: exitPress, at: 2.6) == nil)
    #expect(d.update(pad: 0, buttons: exitPress, at: 3.6) == .exit)
}
@Test func bothCombosHeldIsNeither() {
    var d = ComboDetector()
    for t in stride(from: 0.0, through: 3.0, by: 0.5) {
        #expect(d.update(pad: 0, buttons: [.l1, .r1, .start, .select], at: t) == nil)
    }
}
@Test func changingComboRestartsTimer() {
    var d = ComboDetector()
    _ = d.update(pad: 0, buttons: sleepPress, at: 0)
    _ = d.update(pad: 0, buttons: exitPress, at: 1.5)
    #expect(d.update(pad: 0, buttons: exitPress, at: 3.4) == nil)
    #expect(d.update(pad: 0, buttons: exitPress, at: 3.5) == .exit)
}
