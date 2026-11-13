// SPDX-License-Identifier: GPL-3.0-or-later
import GameController
import RetromacCore

enum ControllerDetector {
    static func detect() -> [ControllerProfile] {
        GCController.controllers()
            .filter { $0.extendedGamepad != nil }
            .map { ControllerProfile(deviceName: $0.vendorName ?? "Controller",
                                     kind: ControllerKind(productCategory: $0.productCategory)) }
    }
}
