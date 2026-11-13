// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let xbox = ControllerProfile(deviceName: "Xbox Wireless Controller", kind: .xbox)
let pro = ControllerProfile(deviceName: "Pro Controller", kind: .nintendo)

@Test func positionPolicyMapsByPositionForEveryPlayer() {
    let k = ControllerBinds.keys(for: [xbox], policy: .position)
    for n in 1...4 {
        #expect(k["input_player\(n)_a_btn"] == "8"); #expect(k["input_player\(n)_b_btn"] == "0")
        #expect(k["input_player\(n)_x_btn"] == "9"); #expect(k["input_player\(n)_y_btn"] == "1")
    }
}
@Test func labelPolicySwapsWhenAllPadsAreXbox() {
    let k = ControllerBinds.keys(for: [xbox, xbox], policy: .label)
    #expect(k["input_player2_a_btn"] == "0"); #expect(k["input_player2_b_btn"] == "8")
    #expect(k["input_player2_x_btn"] == "1"); #expect(k["input_player2_y_btn"] == "9")
}
@Test func labelPolicyKeepsPositionWhenPadsAreMixed() {
    #expect(ControllerBinds.keys(for: [xbox, pro], policy: .label)["input_player1_a_btn"] == "8")
    #expect(ControllerBinds.keys(for: [], policy: .label)["input_player1_a_btn"] == "8")
}
@Test func hotkeysSelectPlusStartExits() {
    let k = ControllerBinds.keys(for: [], policy: .position)
    #expect(k["input_enable_hotkey_btn"] == "2"); #expect(k["input_exit_emulator_btn"] == "3")
}
