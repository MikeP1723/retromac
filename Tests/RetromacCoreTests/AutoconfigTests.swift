// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func positionPolicyMapsByPosition() {
    let s = AutoconfigRenderer.render(.init(deviceName: "Xbox Wireless Controller", kind: .xbox), policy: .position)
    #expect(s.contains("input_a_btn = \"8\"")); #expect(s.contains("input_b_btn = \"0\""))
    #expect(s.contains("input_x_btn = \"9\"")); #expect(s.contains("input_y_btn = \"1\""))
}
@Test func labelPolicySwapsOnlyXbox() {
    let x = AutoconfigRenderer.render(.init(deviceName: "Xbox Wireless Controller", kind: .xbox), policy: .label)
    #expect(x.contains("input_a_btn = \"0\"")); #expect(x.contains("input_b_btn = \"8\""))
    #expect(x.contains("input_x_btn = \"1\"")); #expect(x.contains("input_y_btn = \"9\""))
    let n = AutoconfigRenderer.render(.init(deviceName: "Pro Controller", kind: .nintendo), policy: .label)
    #expect(n.contains("input_a_btn = \"8\""))
}
@Test func headerDriverAndHotkeys() {
    let s = AutoconfigRenderer.render(.init(deviceName: "DualSense Wireless Controller", kind: .playstation), policy: .position)
    #expect(s.hasPrefix("# Managed by retromac — edits will be overwritten\n"))
    #expect(s.contains("input_driver = \"mfi\"")); #expect(s.contains("input_device = \"DualSense Wireless Controller\""))
    #expect(s.contains("input_enable_hotkey_btn = \"2\"")); #expect(s.contains("input_exit_emulator_btn = \"3\""))
}
@Test func analogAxesMapped() {
    let s = AutoconfigRenderer.render(.init(deviceName: "Pad", kind: .generic), policy: .position)
    #expect(s.contains("input_l_x_plus_axis = \"+0\"")); #expect(s.contains("input_r_y_minus_axis = \"-3\""))
}
@Test func fileNameSanitized() {
    #expect(AutoconfigRenderer.fileName(for: .init(deviceName: "Pad: A/B", kind: .generic)) == "Pad_ A_B.cfg")
}
