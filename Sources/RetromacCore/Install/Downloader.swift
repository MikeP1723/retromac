// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol Downloader: Sendable {
    func download(_ url: URL, to dest: URL) async throws
}

public struct URLSessionDownloader: Downloader {
    let headers: [String: String]

    public init(headers: [String: String] = [:]) {
        self.headers = headers
    }

    public func download(_ url: URL, to dest: URL) async throws {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL, userInfo: [NSURLErrorFailingURLErrorKey: url]) }
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (tmp, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url])
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tmp, to: dest)
    }
}
