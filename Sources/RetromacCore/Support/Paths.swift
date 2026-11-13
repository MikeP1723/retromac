// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct Paths: Sendable {
    public let home: URL
    public let applications: URL

    public init(home: URL, applications: URL = URL(filePath: "/Applications")) {
        self.home = home
        self.applications = applications
    }

    public var retromacRoot: URL { home.appending(path: "retromac") }
    public var profile: URL { retromacRoot.appending(path: "profile.json") }
    public var state: URL { retromacRoot.appending(path: "state.json") }
    public var backups: URL { retromacRoot.appending(path: "backups") }
    public var defaultLibraryRoot: URL { retromacRoot.appending(path: "Library") }

    public var retroarchSupport: URL { home.appending(path: "Library/Application Support/RetroArch") }
    public var retroarchConfig: URL { retroarchSupport.appending(path: "config/retroarch.cfg") }
    public var retroarchCores: URL { retroarchSupport.appending(path: "cores") }
    public var globalShaderPreset: URL { retroarchSupport.appending(path: "config/global.slangp") }
    public var retroarchShadersSlang: URL { retroarchSupport.appending(path: "shaders/shaders_slang") }

    public func coreOverride(libraryName: String) -> URL {
        retroarchSupport.appending(path: "config/\(libraryName)/\(libraryName).cfg")
    }

    public var esdeSettings: URL { home.appending(path: "ES-DE/settings/es_settings.xml") }
    public var esdeCustomSystems: URL { home.appending(path: "ES-DE/custom_systems/es_systems.xml") }
}
