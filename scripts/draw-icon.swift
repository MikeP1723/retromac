// SPDX-License-Identifier: GPL-3.0-or-later
// Draws the app icon's layers into Support/AppIcon.icon/Assets (open that in Icon Composer to adjust the
// glass) and a flat preview at build/icon-preview.png. Run: swift scripts/draw-icon.swift
import AppKit

let S: CGFloat = 1024
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
// y-down rect helper
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: S - y - h, width: w, height: h) }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: S - y) }

func render(_ name: String, mask: Bool = false, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if mask {
        ctx.addPath(CGPath(roundedRect: R(100, 100, 824, 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.clip()
        ctx.translateBy(x: 100, y: 100); ctx.scaleBy(x: 824 / S, y: 824 / S)
    }
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: name))
}

func background(_ c: CGContext) {
    let g = CGGradient(colorsSpace: nil, colors: [color(0x2B1D6B), color(0x7A2E8E), color(0xF2607A)] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(g, start: P(512, 0), end: P(512, S), options: [])
}

func tv(_ c: CGContext) {
    c.setLineCap(.round)
    // antennas
    c.setStrokeColor(color(0xF4EADB)); c.setLineWidth(20)
    c.move(to: P(512, 262)); c.addLine(to: P(392, 128))
    c.move(to: P(512, 262)); c.addLine(to: P(648, 112))
    c.strokePath()
    c.setFillColor(color(0xF4EADB))
    for p in [P(392, 128), P(648, 112)] { c.fillEllipse(in: CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)) }
    // feet
    c.setFillColor(color(0xC4B299))
    for x in [CGFloat(282), 662] { c.addPath(CGPath(roundedRect: R(x, 760, 80, 64), cornerWidth: 20, cornerHeight: 20, transform: nil)) }
    c.fillPath()
    // body
    let body = CGPath(roundedRect: R(176, 250, 672, 530), cornerWidth: 120, cornerHeight: 120, transform: nil)
    c.saveGState(); c.addPath(body); c.clip()
    let g = CGGradient(colorsSpace: nil, colors: [color(0xFBF4E8), color(0xE2D3BC)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: P(512, 250), end: P(512, 780), options: [])
    c.restoreGState()
    // knobs
    for y in [CGFloat(392), 500] {
        c.setFillColor(color(0x9E8A70)); c.fillEllipse(in: R(724, y - 40, 80, 80))
        c.setFillColor(color(0xD9C8AE)); c.fillEllipse(in: R(734, y - 30, 60, 60))
        c.setFillColor(color(0x9E8A70)); c.fill(R(759, y - 28, 10, 26))
    }
    // speaker grille
    c.setStrokeColor(color(0xB09C80)); c.setLineWidth(12)
    for y in stride(from: CGFloat(600), through: 690, by: 30) { c.move(to: P(730, y)); c.addLine(to: P(798, y)) }
    c.strokePath()
    // screen bezel
    c.setFillColor(color(0x3A3346))
    c.addPath(CGPath(roundedRect: R(222, 300, 472, 430), cornerWidth: 86, cornerHeight: 86, transform: nil)); c.fillPath()
}

func screen(_ c: CGContext) {
    let glass = CGPath(roundedRect: R(242, 320, 432, 390), cornerWidth: 72, cornerHeight: 72, transform: nil)
    c.saveGState(); c.addPath(glass); c.clip()
    let g = CGGradient(colorsSpace: nil, colors: [color(0x1C3A5C), color(0x0C1224)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: P(458, 515), startRadius: 0, endCenter: P(458, 515), endRadius: 300, options: [.drawsAfterEndLocation])
    // pixel play triangle with glow
    let px: CGFloat = 30, cols = 7, rows = 9
    let ox = 458 - CGFloat(cols) * px / 2 + 12, oy = 515 - CGFloat(rows) * px / 2
    c.setShadow(offset: .zero, blur: 40, color: color(0x5CF2D6, 0.9))
    c.setFillColor(color(0x6BF5DC))
    for col in 0..<cols {
        let half = Int((4 - Double(col) * 4 / 6).rounded())
        for row in (4 - half)...(4 + half) { c.fill(R(ox + CGFloat(col) * px, oy + CGFloat(row) * px, px - 4, px - 4)) }
    }
    c.setShadow(offset: .zero, blur: 0, color: nil)
    // scanlines
    c.setFillColor(color(0x000000, 0.18))
    for y in stride(from: CGFloat(320), to: 710, by: 10) { c.fill(R(242, y, 432, 4)) }
    // glass highlight
    c.setFillColor(color(0xFFFFFF, 0.08))
    c.addPath(CGPath(roundedRect: R(266, 334, 150, 36), cornerWidth: 18, cornerHeight: 18, transform: nil)); c.fillPath()
    c.restoreGState()
}

let assets = "Support/AppIcon.icon/Assets/"
try! FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
render(assets + "background.png", background)
render(assets + "tv.png", tv)
render(assets + "screen.png", screen)
render("build/icon-preview.png", mask: true) { background($0); tv($0); screen($0) }
