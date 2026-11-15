// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func mergeReplacesOwnedKeysAndKeepsTheRest() {
    let existing = "# Dolphin\n[General]\nISOPath0 = /old\nRecursiveISOPaths = True\n\n[Custom]\nKeep = 1\n"
    let out = IniConfig.merge(existing: existing, owned: ["General": ["ISOPath0": "/new"]])
    #expect(out == "# Dolphin\n[General]\nISOPath0 = /new\nRecursiveISOPaths = True\n\n[Custom]\nKeep = 1\n")
}
@Test func mergeAddsMissingKeyToExistingSection() {
    let out = IniConfig.merge(existing: "[Display]\nRenderToMain = True\n\n[Core]\nCPUCore = 4\n", owned: ["Display": ["Fullscreen": "True"]])
    #expect(out == "[Display]\nRenderToMain = True\nFullscreen = True\n\n[Core]\nCPUCore = 4\n")
}
@Test func mergeAddsMissingSection() {
    let out = IniConfig.merge(existing: "[Core]\nCPUCore = 4\n", owned: ["Interface": ["ConfirmStop": "False"], "Analytics": ["Enabled": "False", "PermissionAsked": "True"]])
    #expect(out == "[Core]\nCPUCore = 4\n\n[Analytics]\nEnabled = False\nPermissionAsked = True\n\n[Interface]\nConfirmStop = False\n")
}
@Test func mergeIsIdempotent() {
    let owned = ["General": ["ISOPaths": "2"], "Display": ["Fullscreen": "True"]]
    let once = IniConfig.merge(existing: "[General]\nX = 1\n", owned: owned)
    #expect(IniConfig.merge(existing: once, owned: owned) == once)
}
@Test func mergeOfEmptyFile() {
    #expect(IniConfig.merge(existing: "", owned: ["Settings": ["InternalResolution": "3"]]) == "[Settings]\nInternalResolution = 3\n")
}
@Test func valueWithALineBreakIsNeverWritten() {
    // A value can't add lines (or sections) to the file: a filename with a line break would otherwise do just that.
    let out = IniConfig.merge(existing: "[Filenames]\nBIOS = old.bin\n", owned: ["Filenames": ["BIOS": "x.bin\n[Hotkeys]\nShutdownVM = Keyboard/A"],
                                                                                "UI": ["StartFullscreen": "true"]])
    #expect(out == "[Filenames]\nBIOS = old.bin\n\n[UI]\nStartFullscreen = true\n")
    #expect(!IniConfig.merge(existing: "", owned: ["A": ["k": "a\u{2028}b"]]).contains("\u{2028}"))
}
