// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct Candidate: Equatable, Sendable {
    public var version: String
    public var url: URL
}

/// Finds the newest upstream build for a manifest entry (maintainer tooling, not the app).
public enum UpstreamResolver {
    public static func endpoint(_ u: Upstream) -> URL {
        switch u.kind {
        case .githubRelease:
            return URL(string: "https://api.github.com/repos/\(u.project)/releases/latest")!
        case .gitlabRelease:
            let project = u.project.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
            return URL(string: "https://gitlab.com/api/v4/projects/\(project)/releases")!
        case .libretroStable:
            return URL(string: "https://buildbot.libretro.com/stable/")!
        }
    }

    public static func resolve(_ u: Upstream, body: Data) -> Candidate? {
        switch u.kind {
        case .githubRelease:
            struct Release: Decodable {
                struct Asset: Decodable { let name: String; let browser_download_url: URL }
                let tag_name: String
                let assets: [Asset]
            }
            guard let release = try? JSONDecoder().decode(Release.self, from: body),
                  let asset = release.assets.first(where: { matches(u.assetPattern, $0.name) }) else { return nil }
            return Candidate(version: stripV(release.tag_name), url: asset.browser_download_url)
        case .gitlabRelease:
            struct Release: Decodable {
                struct Assets: Decodable {
                    struct Link: Decodable { let name: String; let url: URL }
                    let links: [Link]
                }
                let tag_name: String
                let assets: Assets
            }
            guard let release = (try? JSONDecoder().decode([Release].self, from: body))?.first,
                  let link = release.assets.links.first(where: { matches(u.assetPattern, $0.name) }) else { return nil }
            return Candidate(version: stripV(release.tag_name), url: link.url)
        case .libretroStable:
            // Directory links appear as href="/stable/1.22.2/" (or relative "1.22.2/").
            let html = String(decoding: body, as: UTF8.self)
            let regex = /href="(?:\/stable\/)?(\d+(?:\.\d+)+)\/"/
            let versions = html.matches(of: regex).map { String($0.1) }
            guard let newest = versions.max(by: { SemVer.compare($0, $1) == .orderedAscending }),
                  let url = URL(string: u.assetPattern.replacingOccurrences(of: "{version}", with: newest)) else { return nil }
            return Candidate(version: newest, url: url)
        }
    }

    static func matches(_ pattern: String, _ name: String) -> Bool {
        name.range(of: pattern, options: .regularExpression) != nil
    }

    static func stripV(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}
