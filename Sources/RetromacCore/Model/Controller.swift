// SPDX-License-Identifier: GPL-3.0-or-later

public enum ControllerKind: String, Codable, Sendable {
    case xbox, playstation, nintendo, generic

    /// Classifies from `GCController.productCategory`.
    public init(productCategory: String) {
        let c = productCategory.lowercased()
        if c.contains("xbox") {
            self = .xbox
        } else if c.contains("dualsense") || c.contains("dualshock") {
            self = .playstation
        } else if c.contains("switch pro") || c.contains("pro controller") {
            self = .nintendo
        } else {
            self = .generic
        }
    }
}

public struct ControllerProfile: Codable, Equatable, Sendable {
    /// `GCController.vendorName`, which RetroArch's mfi driver reports as the device name.
    public var deviceName: String
    public var kind: ControllerKind

    public init(deviceName: String, kind: ControllerKind) {
        self.deviceName = deviceName
        self.kind = kind
    }
}
