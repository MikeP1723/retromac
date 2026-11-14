// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network
import Testing
@testable import RetromacCore

/// Records what was sent; answers `request` with a scripted reply (nil = timeout).
final class FakeTransport: DatagramTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []
    let reply: String?

    init(reply: String?) { self.reply = reply }

    var sent: [String] { lock.withLock { _sent } }

    func send(_ text: String) async throws { lock.withLock { _sent.append(text) } }
    func request(_ text: String, timeout: TimeInterval) async throws -> String? {
        lock.withLock { _sent.append(text) }
        return reply
    }
}

@Test func pausesOnlyWhenPlaying() async {
    let playing = FakeTransport(reply: "GET_STATUS PLAYING snes,Game.sfc,crc32=1a2b3c4d\n")
    await RetroArchCommands(transport: playing).pauseIfPlaying()
    #expect(playing.sent == ["GET_STATUS", "PAUSE_TOGGLE"])

    let paused = FakeTransport(reply: "GET_STATUS PAUSED snes,Game.sfc,crc32=1a2b3c4d\n")
    await RetroArchCommands(transport: paused).pauseIfPlaying()
    #expect(paused.sent == ["GET_STATUS"])
}
@Test func noReplyMeansNoToggle() async {
    let silent = FakeTransport(reply: nil)
    await RetroArchCommands(transport: silent).pauseIfPlaying()
    #expect(silent.sent == ["GET_STATUS"])
}
@Test func quitSendsQuit() async {
    let t = FakeTransport(reply: nil)
    await RetroArchCommands(transport: t).quit()
    #expect(t.sent == ["QUIT"])
}
@Test func parsesStatuses() {
    #expect(PlaybackState.parse("GET_STATUS PLAYING snes,Game.sfc,crc32=1a2b3c4d\n") == .playing)
    #expect(PlaybackState.parse("GET_STATUS PAUSED n64,Game.z64,crc32=0\n") == .paused)
    #expect(PlaybackState.parse("GET_STATUS CONTENTLESS") == .contentless)
    #expect(PlaybackState.parse("garbage") == .unknown)
    #expect(PlaybackState.parse("") == .unknown)
}

/// A loopback UDP responder standing in for RetroArch; replies `reply` to every datagram.
private func responder(reply: String) async throws -> NWListener {
    let parameters = NWParameters.udp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    let queue = DispatchQueue(label: "test-responder")
    listener.newConnectionHandler = { connection in
        connection.start(queue: queue)
        connection.receiveMessage { _, _, _, _ in
            connection.send(content: Data(reply.utf8), completion: .idempotent)
        }
    }
    listener.start(queue: queue)
    for _ in 0..<100 where listener.port == nil || listener.port?.rawValue == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
    return listener
}

@Test func udpRequestGetsReply() async throws {
    let listener = try await responder(reply: "GET_STATUS PAUSED snes,Game.sfc,crc32=0\n")
    defer { listener.cancel() }
    let port = try #require(listener.port)
    let reply = try await UDPTransport(port: port).request("GET_STATUS", timeout: 2)
    #expect(reply.map(PlaybackState.parse) == .paused)
}
@Test func udpRequestWithNobodyListeningIsNil() async throws {
    // Grab a free port, then close it so nothing answers.
    let listener = try await responder(reply: "")
    let port = try #require(listener.port)
    listener.cancel()
    let start = Date()
    let reply = try? await UDPTransport(port: port).request("GET_STATUS", timeout: 1)
    #expect(reply == nil)
    #expect(Date().timeIntervalSince(start) < 3)
}
