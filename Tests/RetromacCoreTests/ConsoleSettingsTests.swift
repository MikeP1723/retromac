// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func oldProfilesDecodeWithoutConsole() throws {
    let url = try makeTempDir().appending(path: "p.json")
    try profile().save(to: url)
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    json.removeValue(forKey: "console")
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    #expect(try Profile.load(from: url).console == nil)
}
@Test func consoleModeNeverOpensTheNetworkCommandPort() throws {
    // RetroArch binds its command port on every interface (*:55355), so it stays off; console mode pauses
    // by hiding RetroArch, which pause_nonactive turns into a pause.
    var p = profile()
    p.console = ConsoleSettings(enabled: true, sleep: .standby)
    let on = retroarchKeys(try render(p))
    #expect(on["network_cmd_enable"] == "false" && on["network_cmd_port"] == nil)
    #expect(on["pause_nonactive"] == "true")
    #expect(retroarchKeys(try render(profile()))["network_cmd_enable"] == "false")
    #expect(ConsoleSettings.default == ConsoleSettings(enabled: false, sleep: .standby))
}
@Test func consolePaths() {
    let p = Paths(home: URL(filePath: "/tmp/h"))
    #expect(p.consoleSession.path == "/tmp/h/Library/Application Support/retromac/console-session.json")
    #expect(p.consoleAgentPlist.path == "/tmp/h/Library/LaunchAgents/petersoft.retromac.console.plist")
}
