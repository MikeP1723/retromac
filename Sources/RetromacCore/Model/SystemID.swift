// SPDX-License-Identifier: GPL-3.0-or-later

/// Every console retromac recognizes. Raw values are ES-DE's system folder names.
public enum SystemID: String, Codable, CaseIterable, Sendable {
    case nes, snes, genesis, n64, psx, ps2, saturn, gc, wii, xbox, wiiu, `switch`

    public var displayName: String {
        switch self {
        case .nes: "Nintendo Entertainment System"
        case .snes: "Super Nintendo"
        case .genesis: "Sega Genesis"
        case .n64: "Nintendo 64"
        case .psx: "PlayStation"
        case .ps2: "PlayStation 2"
        case .saturn: "Sega Saturn"
        case .gc: "GameCube"
        case .wii: "Wii"
        case .xbox: "Xbox"
        case .wiiu: "Wii U"
        case .switch: "Nintendo Switch"
        }
    }

    public var isCartridge: Bool {
        switch self {
        case .nes, .snes, .genesis, .n64: true
        default: false
        }
    }
}
