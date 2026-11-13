// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol CommandRunner: Sendable {
    @discardableResult func run(_ executable: String, _ args: [String]) throws -> String
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    /// Runs to completion; non-zero exit throws with stderr. Intended for tools with small output.
    @discardableResult
    public func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.commandFailed(executable, process.terminationStatus, String(decoding: stderr, as: UTF8.self))
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
