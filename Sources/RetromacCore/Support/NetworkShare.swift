// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import NetFS

public enum NetworkShareError: Error, Equatable {
    /// The user closed macOS's login prompt.
    case cancelled
    case unreachable(String)
    /// The share mounted, but the library's folder isn't in it.
    case folderMissing(String)
}

public protocol ShareMounter: Sendable {
    /// Mounts `share` and returns its mount point.
    func mount(_ share: URL) throws -> URL
    /// Mounted network volumes and the URLs they were mounted from.
    func mounted() -> [(remount: URL, mountPoint: URL)]
}

/// Mounts through NetFS with macOS's own login UI allowed: macOS asks for the password and can keep it in
/// the Keychain, so retromac never handles it.
public struct NetFSMounter: ShareMounter {
    /// Whether macOS may show its server login. Only retromac.app allows it; the console agent doesn't, since
    /// its play notification is unauthenticated and the prompt could appear over ES-DE.
    let allowUI: Bool

    public init(allowUI: Bool = true) { self.allowUI = allowUI }

    static func openOptions(allowUI: Bool) -> NSMutableDictionary {
        let open = NSMutableDictionary()
        open[kNAUIOptionKey] = allowUI ? kNAUIOptionAllowUI : kNAUIOptionNoUI
        return open
    }

    /// What NetFS is asked: a guest share (Finder's `GUEST:@host/share`; the empty password isn't kept) is
    /// mounted as guest, with no user, or NetFS asks for credentials a guest login doesn't have.
    static func request(for share: URL, allowUI: Bool) -> (url: URL, options: NSMutableDictionary) {
        let options = openOptions(allowUI: allowUI)
        guard share.user()?.lowercased() == "guest", var c = URLComponents(url: share, resolvingAgainstBaseURL: false) else {
            return (share, options)
        }
        c.user = nil
        c.password = nil
        options[kNetFSUseGuestKey] = true
        return (c.url ?? share, options)
    }

    public func mount(_ share: URL) throws -> URL {
        let (url, open) = Self.request(for: share, allowUI: allowUI)
        var points: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(url as CFURL, nil, nil, nil, open, nil, &points)
        if status == 0, let point = (points?.takeRetainedValue() as? [String])?.first {
            return URL(filePath: point, directoryHint: .isDirectory)
        }
        switch status {
        case ECANCELED, -128: throw NetworkShareError.cancelled  // -128: userCanceledErr
        case EEXIST:
            if let point = NetworkShare.match(share, in: mounted()) { return point }
            throw NetworkShareError.unreachable(String(cString: strerror(EEXIST)))
        default:
            throw NetworkShareError.unreachable(status > 0 ? String(cString: strerror(status)) : "error \(status)")
        }
    }

    public func mounted() -> [(remount: URL, mountPoint: URL)] {
        let keys: [URLResourceKey] = [.volumeURLForRemountingKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .compactMap { point in
                guard let remount = try? point.resourceValues(forKeys: Set(keys)).volumeURLForRemounting else { return nil }
                return (remount: remount, mountPoint: point)
            }
    }
}

public struct NetworkShare: Sendable {
    let mounter: any ShareMounter

    public init(mounter: any ShareMounter = NetFSMounter()) { self.mounter = mounter }

    /// The library's folder: from the share's existing mount (whatever /Volumes name it got, whoever
    /// mounted it), or a new one.
    public func libraryFolder(for library: NetworkLibrary) throws -> URL {
        let point = try Self.match(library.share, in: mounter.mounted()) ?? mounter.mount(library.share)
        let folder = library.subpath.isEmpty ? point : point.appending(path: library.subpath, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NetworkShareError.folderMissing(library.subpath)
        }
        return folder
    }

    /// Same server and share, ignoring letter case and the user name. Finder mounts a browsed server under
    /// its Bonjour service name (`petersoft._smb._tcp.local`), the same machine as `petersoft.local`/`petersoft`.
    static func match(_ share: URL, in mounts: [(remount: URL, mountPoint: URL)]) -> URL? {
        func key(_ url: URL) -> String? {
            guard var host = url.host(percentEncoded: false)?.lowercased(),
                  let name = url.pathComponents.dropFirst().first?.lowercased() else { return nil }
            for suffix in ["._smb._tcp.local", "._smb._tcp", ".local"] where host.hasSuffix(suffix) {
                host.removeLast(suffix.count)
                break
            }
            return "\(url.scheme?.lowercased() ?? "")://\(host)/\(name)"
        }
        guard let wanted = key(share) else { return nil }
        return mounts.first { key($0.remount) == wanted }?.mountPoint
    }
}
