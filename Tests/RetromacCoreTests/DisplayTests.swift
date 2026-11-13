// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let tv65_4k = DisplayProfile(widthPx: 3840, heightPx: 2160, refreshHz: 120, hdr: true, vrr: true, diagonalInches: 65, distanceInches: 72)
let tv55_4k_far = DisplayProfile(widthPx: 3840, heightPx: 2160, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 55, distanceInches: 120)
let tv55_1080 = DisplayProfile(widthPx: 1920, heightPx: 1080, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 55, distanceInches: 96)
let monitor720 = DisplayProfile(widthPx: 1280, heightPx: 720, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 24, distanceInches: 30)

@Test func ppdMatchesHandCalculation() {
    #expect(abs(Optics.pixelsPerDegree(tv65_4k) - 89.4) < 0.1)
    #expect(abs(Optics.pixelsPerDegree(tv55_4k_far) - 170.0) < 0.1)
}
@Test func crtTierSelection() throws {
    let r = try DisplayRules.bundled()
    #expect(r.shaderPreset(for: tv65_4k, look: .crt)?.path == "crt/crt-guest-advanced.slangp")
    #expect(r.shaderPreset(for: tv55_4k_far, look: .crt)?.path == "crt/crt-easymode.slangp")
    #expect(r.shaderPreset(for: tv55_1080, look: .crt)?.path == "crt/crt-easymode.slangp")
    #expect(r.shaderPreset(for: monitor720, look: .crt) == nil)
}
@Test func crispHasNoShaderSmoothAlwaysDoes() throws {
    let r = try DisplayRules.bundled()
    #expect(r.shaderPreset(for: tv65_4k, look: .crisp) == nil)
    #expect(r.shaderPreset(for: monitor720, look: .smooth)?.path == "interpolation/sharp-bilinear-simple.slangp")
}
@Test func everyPresetLicenseIsVendorCompatible() throws {
    let r = try DisplayRules.bundled()
    for p in r.crtTiers.map(\.preset) + [r.smoothPreset] { #expect(LicensePolicy.vendoredAllowed.contains(p.license)) }
}
@Test func profileRoundTrips() throws {
    let dir = try makeTempDir()
    let url = dir.appending(path: "nested/profile.json")
    let p = Profile(display: tv65_4k, look: .crt, systems: [.nes, .n64],
                    controllers: [ControllerProfile(deviceName: "Xbox Wireless Controller", kind: .xbox)],
                    facePolicy: .label, libraryRoot: dir.appending(path: "Library"))
    try p.save(to: url)
    #expect(try Profile.load(from: url) == p)
}
@Test func classifiesKnownCategories() {
    #expect(ControllerKind(productCategory: "Xbox One") == .xbox)
    #expect(ControllerKind(productCategory: "DualSense") == .playstation)
    #expect(ControllerKind(productCategory: "Switch Pro Controller") == .nintendo)
    #expect(ControllerKind(productCategory: "8BitDo Something") == .generic)
}
