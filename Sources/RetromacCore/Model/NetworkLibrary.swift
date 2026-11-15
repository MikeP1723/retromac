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
        var rest = Substring(trimmed.dropFirst("smb://".count))
        // User info first, at the last "@": a password may itself contain "/" or "@". Only the user name is
        // kept; the address is saved in profile.json, and macOS's login prompt asks for the password.
        var user = ""
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            rest = rest[rest.index(after: at)...]
        }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // What's read here as user and host must be what URL reads: nothing that ends the authority early.
        guard parts.count >= 2, !parts[0].isEmpty,
              !user.contains(where: { "/?#".contains($0) }), !parts[0].contains(where: { "?#".contains($0) }) else { return nil }
        let authority = (user.isEmpty ? "" : "\(user)@") + parts[0]
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let path = parts.dropFirst().map { ($0.removingPercentEncoding ?? $0).addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        guard let url = URL(string: "smb://\(authority)/" + path.joined(separator: "/")),
              url.host(percentEncoded: false)?.lowercased() == parts[0].split(separator: ":").first.map({ $0.lowercased() }) else { return nil }
        return url
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

    /// The consoles whose ES-DE folder name is in `folder` (any letter case: SMB mounts are case-insensitive),
    /// and the other folders, so the user can see what to rename.
    public static func consoleFolders(in folder: URL) -> (found: [SystemID], other: [String]) {
        let names = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
        let found = SystemID.allCases.filter { system in names.contains { $0.caseInsensitiveCompare(system.rawValue) == .orderedSame } }
        let other = names.filter { name in !SystemID.allCases.contains { name.caseInsensitiveCompare($0.rawValue) == .orderedSame } }
        return (found, other.sorted())
    }
}
