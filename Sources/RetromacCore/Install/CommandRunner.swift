// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol CommandRunner: Sendable {
    @discardableResult func run(_ executable: String, _ args: [String], input: String?) throws -> String
}

extension CommandRunner {
    @discardableResult
    public func run(_ executable: String, _ args: [String]) throws -> String {
        try run(executable, args, input: nil)
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    /// Runs to completion; non-zero exit throws with stderr. Intended for tools with small output.
    @discardableResult
    public func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(["PAGER": "cat"]) { $1 }
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin
        try process.run()
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.commandFailed(executable, process.terminationStatus, String(decoding: stderr, as: UTF8.self))
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
