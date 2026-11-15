// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func tomlMergeKeepsUnknownTablesAndKeys() {
    let existing = "[general]\nshow_welcome = true\nlast_viewed_menu_index = 2\n\n[audio]\nvolume_limit = 0.5\n"
    let out = TomlConfig.merge(existing: existing, owned: ["general": ["show_welcome": .bool(false)]])
    #expect(out == "[general]\nshow_welcome = false\nlast_viewed_menu_index = 2\n\n[audio]\nvolume_limit = 0.5\n")
}
@Test func tomlMergeAddsMissingTable() {
    let out = TomlConfig.merge(existing: "[general]\nshow_welcome = false\n", owned: ["display.quality": ["surface_scale": .int(3)]])
    #expect(out == "[general]\nshow_welcome = false\n\n[display.quality]\nsurface_scale = 3\n")
}
@Test func tomlStringEscaping() {
    #expect(TomlValue.string(#"/Mike's "Games"\x"#).rendered == #""/Mike's \"Games\"\\x""#)
    #expect(TomlValue.string("a\tb\u{1}").rendered == #""a\u0009b\u0001""#)
    #expect(TomlValue.bool(true).rendered == "true" && TomlValue.int(4).rendered == "4")
}
