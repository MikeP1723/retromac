// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A game library on a server share (`smb://host/share/sub/folder`), read-only to retromac.
public struct NetworkLibrary: Codable, Equatable, Sendable {
    /// The share and sub-folder, percent-encoded.
    public var url: URL
    /// The local library to go back to when the network library is turned off.
    public var localLibrary: URL

    public init(url: URL, localLibrary: URL) {
        self.url = url
        self.localLibrary = localLibrary
    }

    /// An `smb://` address as typed (any letter case, spaces, a trailing slash), or nil. It needs a host and a
    /// share. SMB only: AFP is deprecated in macOS, and NFS export paths don't split into share and folder.
    public static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("smb://") else { return nil }
        let rest = trimmed.dropFirst("smb://".count)
        let parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let path = parts.dropFirst().map { ($0.removingPercentEncoding ?? $0).addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        return URL(string: "smb://\(parts[0])/" + path.joined(separator: "/"))
    }

    private var encodedParts: [Substring] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "").split(separator: "/")
    }

    /// What gets mounted: `smb://[user@]host/<share>`.
    public var share: URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.percentEncodedPath = "/" + (encodedParts.first.map(String.init) ?? "")
        return c.url ?? url
    }

    /// The library's folder inside the share, or "" for the share itself.
    public var subpath: String {
        encodedParts.dropFirst().map { $0.removingPercentEncoding ?? String($0) }.joined(separator: "/")
    }
}
