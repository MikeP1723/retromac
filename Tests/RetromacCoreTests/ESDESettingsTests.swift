// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func esdeReplacesROMDirectoryLine() {
    let input = "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n<string name=\"ROMDirectory\" value=\"/old\" />\n"
    #expect(ESDESettings.merge(existing: input, romDirectory: "/Users/me/retromac/Library")
        == "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n<string name=\"ROMDirectory\" value=\"/Users/me/retromac/Library\" />\n")
}
@Test func esdeCreatesFileWhenMissing() {
    #expect(ESDESettings.merge(existing: nil, romDirectory: "/a b/&c")
        == "<?xml version=\"1.0\"?>\n<string name=\"ROMDirectory\" value=\"/a b/&amp;c\" />\n")
}
@Test func esdeAppendsWhenAbsent() {
    #expect(ESDESettings.merge(existing: "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n", romDirectory: "/r")
        == "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n<string name=\"ROMDirectory\" value=\"/r\" />\n")
}
