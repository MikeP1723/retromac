// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idle-sleeping (the display still sleeps) so a controller can wake it in standby.
@MainActor
final class StandbyAssertion {
    private var id: IOPMAssertionID = 0
    private var held = false

    func hold() {
        guard !held else { return }
        held = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "retromac console standby" as CFString, &id) == kIOReturnSuccess
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(id)
        held = false
    }
}

enum Power {
    /// Wakes the display as if the user touched the keyboard.
    static func declareUserActivity() {
        var id: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("retromac controller" as CFString, kIOPMUserActiveLocal, &id)
    }

    static func sleepDisplay() { pmset("displaysleepnow") }
    static func sleepSystem() { pmset("sleepnow") }

    private static func pmset(_ command: String) {
        _ = try? Process.run(URL(filePath: "/usr/bin/pmset"), arguments: [command])
    }
}
