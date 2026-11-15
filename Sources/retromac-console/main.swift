// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// A background agent: no Dock icon, no menu bar, started at login by launchd (see ConsoleAgent).
NSApplication.shared.setActivationPolicy(.accessory)
let controller = AgentController()
controller.start()
NSApplication.shared.run()
