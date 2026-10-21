// Renders the Feel the Noize app icon into an AppIcon.appiconset directory.
// Usage: swift Scripts/render-icon.swift Sources/FeelTheNoize/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    return CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Stops the script with a message on stderr; it runs from build.sh, so a failure must be loud rather than a crash.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-icon: \(message)\n".utf8))
    exit(1)
}

func makeContext(pixels: Int, space: CGColorSpace) -> CGContext {
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        fail("cannot create a \(pixels) pixel context")
    }
    return context
}

func makeGradient(_ colors: [CGColor], locations: [CGFloat], space: CGColorSpace) -> CGGradient {
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
        fail("cannot create a gradient")
    }
    return gradient
}

/// The color `amount` of the way from `a` to `b`, component by component.
func mix(_ a: CGColor, _ b: CGColor, amount: CGFloat) -> CGColor {
    guard let from = a.components else {
        fail("a band color has no components")
    }
    guard let to = b.components else {
        fail("a band color has no components")
    }
    return CGColor(
        srgbRed: from[0] + (to[0] - from[0]) * amount, green: from[1] + (to[1] - from[1]) * amount, blue: from[2] + (to[2] - from[2]) * amount,
        alpha: 1)
}

func pngData(from context: CGContext) -> Data {
    guard let image = context.makeImage() else {
        fail("cannot render the scaled icon")
    }
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fail("cannot encode the icon as PNG")
    }
    return png
}

guard CommandLine.arguments.count > 1 else {
    fail("usage: swift Scripts/render-icon.swift <AppIcon.appiconset>")
}
let outDir = CommandLine.arguments[1]
guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("no sRGB color space")
}

let size: CGFloat = 1024
let ctx = makeContext(pixels: Int(size), space: space)
let center = CGPoint(x: size / 2, y: size / 2)

// Tile: macOS icon grid, 824 pt body centered on the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(rgb(0x1B1E25))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
let tileGradient = makeGradient([rgb(0x343946), rgb(0x15171D)], locations: [0, 1], space: space)
ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()
// Hairline highlight along the tile edge.
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(4)
ctx.strokePath()

// Volume scale: 270 degree sweep from lower left, clockwise, 60 % lit.
let tickCount = 25
let level = 0.6
let startAngle = 225.0
let sweep = 270.0
ctx.setLineCap(.round)
for index in 0 ..< tickCount {
    let fraction = Double(index) / Double(tickCount - 1)
    let angle = (startAngle - fraction * sweep) * .pi / 180
    let inner: CGFloat = 318
    let outer: CGFloat = 356
    let direction = CGPoint(x: cos(angle), y: sin(angle))
    ctx.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
    ctx.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
    ctx.setStrokeColor(fraction <= level ? rgb(0xFFA31A) : rgb(0x4B5160))
    ctx.setLineWidth(16)
    ctx.strokePath()
}

// Knob body with drop shadow.
let knobRadius: CGFloat = 252
let knobRect = CGRect(x: center.x - knobRadius, y: center.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x000000, 0.55))
ctx.setFillColor(rgb(0x8A8F99))
ctx.fillEllipse(in: knobRect)
ctx.restoreGState()

// Brushed aluminum: conic gradient with alternating light and dark bands.
ctx.saveGState()
ctx.addEllipse(in: knobRect)
ctx.clip()
let bands: [CGColor] = [
    rgb(0xE9ECF1), rgb(0xA3A8B2), rgb(0xD9DCE2), rgb(0x9097A3), rgb(0xEEF0F4), rgb(0xA0A6B0), rgb(0xDADDE3), rgb(0x959BA6), rgb(0xE9ECF1)
]
// Conic gradient approximated with thin wedges, interpolating between the band colors.
let slices = 720
ctx.setShouldAntialias(false)
for slice in 0 ..< slices {
    let t = Double(slice) / Double(slices) * Double(bands.count - 1)
    let lower = Int(t)
    let upper = min(lower + 1, bands.count - 1)
    ctx.setFillColor(mix(bands[lower], bands[upper], amount: CGFloat(t - Double(lower))))
    let from = Double.pi / 3 + Double(slice) / Double(slices) * 2 * .pi
    let to = Double.pi / 3 + Double(slice + 1) / Double(slices) * 2 * .pi + 0.002
    ctx.move(to: center)
    ctx.addArc(center: center, radius: knobRadius + 2, startAngle: from, endAngle: to, clockwise: false)
    ctx.closePath()
    ctx.fillPath()
}
ctx.setShouldAntialias(true)
// Light from above: brighten the top, darken the bottom.
let shade = makeGradient([rgb(0xFFFFFF, 0.25), rgb(0x000000, 0.0), rgb(0x000000, 0.28)], locations: [0, 0.5, 1], space: space)
ctx.drawLinearGradient(shade, start: CGPoint(x: 512, y: center.y + knobRadius), end: CGPoint(x: 512, y: center.y - knobRadius), options: [])
ctx.restoreGState()

// Rim: a darker bevel ring and a fine outer edge.
ctx.addEllipse(in: knobRect.insetBy(dx: 3, dy: 3))
ctx.setStrokeColor(rgb(0x5E6470, 0.9))
ctx.setLineWidth(6)
ctx.strokePath()
let faceRect = knobRect.insetBy(dx: 30, dy: 30)
ctx.addEllipse(in: faceRect)
ctx.setStrokeColor(rgb(0x000000, 0.14))
ctx.setLineWidth(5)
ctx.strokePath()
ctx.addEllipse(in: faceRect.offsetBy(dx: 0, dy: -3))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
ctx.setLineWidth(2)
ctx.strokePath()

// Indicator dot at the lit end of the scale.
let indicatorAngle = (startAngle - level * sweep) * .pi / 180
let dotCenter = CGPoint(x: center.x + cos(indicatorAngle) * 178, y: center.y + sin(indicatorAngle) * 178)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 18, color: rgb(0xFFA31A, 0.8))
ctx.setFillColor(rgb(0xFFA31A))
ctx.fillEllipse(in: CGRect(x: dotCenter.x - 24, y: dotCenter.y - 24, width: 48, height: 48))
ctx.restoreGState()

guard let master = ctx.makeImage() else {
    fail("cannot render the master icon")
}

func write(_ pixels: Int, _ name: String) -> Void {
    let small = makeContext(pixels: pixels, space: space)
    small.interpolationQuality = .high
    small.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    do {
        try pngData(from: small).write(to: url)
    }
    catch {
        fail("cannot write \(url.path): \(error)")
    }
}
for points in [16, 32, 128, 256, 512] {
    write(points, "icon_\(points)x\(points).png")
    write(points * 2, "icon_\(points)x\(points)@2x.png")
}
print("rendered")
