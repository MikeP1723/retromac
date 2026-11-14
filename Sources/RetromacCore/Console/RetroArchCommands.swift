// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network
import os

/// One-datagram-at-a-time access to RetroArch's network command interface.
public protocol DatagramTransport: Sendable {
    func send(_ text: String) async throws
    /// Sends `text` and waits for one reply datagram; nil if none arrives within `timeout`.
    func request(_ text: String, timeout: TimeInterval) async throws -> String?
}

/// UDP to RetroArch on localhost (`network_cmd_port`, see ProfileRenderer).
public struct UDPTransport: DatagramTransport {
    let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "petersoft.retromac.retroarch-commands")

    public init(port: NWEndpoint.Port = 55355) {
        self.port = port
    }

    public func send(_ text: String) async throws {
        let connection = open()
        defer { connection.cancel() }
        try await send(text, on: connection)
    }

    public func request(_ text: String, timeout: TimeInterval) async throws -> String? {
        let connection = open()
        defer { connection.cancel() }
        try await send(text, on: connection)
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (String?) -> Void = { reply in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: reply) }
            }
            connection.receiveMessage { data, _, _, _ in
                finish(data.flatMap { String(data: $0, encoding: .utf8) })
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    private func open() -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .udp)
        connection.start(queue: queue)
        return connection
    }

    private func send(_ text: String, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}

public enum PlaybackState: Equatable, Sendable {
    case playing, paused, contentless, unknown

    /// Parses a `GET_STATUS` reply (RetroArch command.c: `GET_STATUS PLAYING|PAUSED <system>,<file>,crc32=…`
    /// or `GET_STATUS CONTENTLESS`).
    public static func parse(_ status: String) -> PlaybackState {
        let words = status.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words[0] == "GET_STATUS" else { return .unknown }
        switch words[1] {
        case "PLAYING": return .playing
        case "PAUSED": return .paused
        case "CONTENTLESS": return .contentless
        default: return .unknown
        }
    }
}

public struct RetroArchCommands {
    let transport: any DatagramTransport

    public init(transport: any DatagramTransport) {
        self.transport = transport
    }

    /// Pauses only a running game, so a repeated sleep combo never unpauses it. RetroArch may not be
    /// running; errors and silence are ignored.
    public func pauseIfPlaying() async {
        guard let reply = try? await transport.request("GET_STATUS", timeout: 1),
              PlaybackState.parse(reply) == .playing else { return }
        try? await transport.send("PAUSE_TOGGLE")
    }

    public func quit() async {
        try? await transport.send("QUIT")
    }
}
