// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func object(_ json: String?) throws -> [String: Any] {
    let text = try #require(json)
    return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Test func ownedKeysAreSetAndOthersKept() throws {
    let input = #"{"version":70,"show_confirm_exit":true,"update_checker_type":"PromptAtStartup","game_dirs":[],"docked_mode":true,"input_config":[{"id":"0-x"}],"res_scale":1}"#
    let out = try object(RyubingConfig.merge(existing: input, gameDir: "/lib/switch", replacing: nil))
    #expect(out["show_confirm_exit"] as? Bool == false)
    #expect(out["update_checker_type"] as? String == "Off")
    #expect(out["game_dirs"] as? [String] == ["/lib/switch"])
    #expect(out["docked_mode"] as? Bool == true)
    #expect(out["input_config"] as? [[String: String]] == [["id": "0-x"]])
    #expect((out["res_scale"] as? NSNumber).map { String(cString: $0.objCType) } == "q")  // still an integer
    #expect(out["res_scale"] as? Int == 1 && out["version"] as? Int == 70)
}

@Test func gameDirsKeepTheirsAndSwapOurs() throws {
    let input = #"{"version":70,"game_dirs":["/mine","/old/switch"]}"#
    func dirs(_ json: String, _ dir: String, _ replacing: String?) throws -> [String]? {
        try object(RyubingConfig.merge(existing: json, gameDir: dir, replacing: replacing))["game_dirs"] as? [String]
    }
    #expect(try dirs(input, "/new/switch", "/old/switch") == ["/mine", "/new/switch"])
    #expect(try dirs(#"{"version":70,"game_dirs":["/new/switch","/mine"]}"#, "/new/switch", nil) == ["/new/switch", "/mine"])
    #expect(try dirs(input, "/new/switch", nil) == ["/mine", "/old/switch", "/new/switch"])
    #expect(try dirs(#"{"version":70}"#, "/new/switch", nil) == ["/new/switch"])
}

@Test func unknownVersionOrBadJSONWritesNothing() {
    for input in [nil, "", "[]", #"{"version":71}"#, #"{"game_dirs":[]}"#] {
        #expect(RyubingConfig.merge(existing: input, gameDir: "/lib/switch", replacing: nil) == nil)
    }
}

@Test func mergeIsStable() throws {
    let input = #"{"version":70,"show_confirm_exit":true,"game_dirs":["/mine"],"res_scale":1,"path":"/a/b"}"#
    let once = try #require(RyubingConfig.merge(existing: input, gameDir: "/lib/switch", replacing: nil))
    #expect(RyubingConfig.merge(existing: once, gameDir: "/lib/switch", replacing: nil) == once)
    #expect(once.contains(#""/a/b""#))
}
