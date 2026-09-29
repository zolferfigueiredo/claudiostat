// DMG window background: the website's desktop wallpaper (.wall in claudiostatwebsite/style.css) with a curved
// arrow from the app (left) to the Applications link (right). Positions must match the Finder script in build.sh.
// build.sh runs this: swift Icon/make-dmg-background.swift <output folder>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 640, height: CGFloat = 400
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r / 255, g / 255, b / 255, a])!
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// CSS linear-gradient(<angle>) over a box: 0deg points up, 90deg right, in y-down coordinates.
func linear(_ ctx: CGContext, _ g: CGGradient, degrees: CGFloat, in box: CGRect) {
    let a = degrees * .pi / 180
    let length = abs(box.width * sin(a)) + abs(box.height * cos(a))
    let dx = sin(a) * length / 2, dy = -cos(a) * length / 2
    ctx.drawLinearGradient(g, start: CGPoint(x: box.midX - dx, y: box.midY - dy),
                           end: CGPoint(x: box.midX + dx, y: box.midY + dy),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// CSS radial-gradient(rx ry at x y, color, transparent stop).
func radial(_ ctx: CGContext, _ color: CGColor, rx: CGFloat, ry: CGFloat, x: CGFloat, y: CGFloat, stop: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x * width, y: y * height)
    ctx.scaleBy(x: rx * width, y: ry * height)
    ctx.drawRadialGradient(gradient([(color, 0), (color.copy(alpha: 0)!, stop)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
    ctx.restoreGState()
}

// The website's star path, in its 100...924 viewBox. Each piece is filled on its own: their windings differ.
func star(in ctx: CGContext) {
    let rays: [[CGPoint]] = [
        [(552.9, 546.5), (565.5, 285.8), (539.0, 279.1), (427.7, 515.3)],
        [(539.7, 470.0), (295.7, 377.4), (281.2, 400.6), (471.4, 579.4)],
        [(463.0, 458.9), (299.5, 662.4), (317.1, 683.3), (545.9, 557.7)],
        [(428.6, 528.5), (571.7, 746.8), (597.0, 736.6), (548.2, 480.1)],
        [(484.2, 582.6), (736.1, 514.0), (734.2, 486.8), (475.2, 453.9)],
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
    for ray in rays { ctx.addLines(between: ray); ctx.closePath(); ctx.fillPath() }
    for (x, y, r) in [(553.0, 279.6, 14.0), (285.9, 387.5, 14), (306.0, 674.8, 14), (585.5, 744.4, 14),
                      (738.1, 500.2, 14), (493.7, 517.3, 66)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}

func draw(scale: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to y-down so every number reads like the CSS it came from.
    ctx.translateBy(x: 0, y: height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)

    linear(ctx, gradient([(rgb(240, 120, 74), 0), (rgb(220, 79, 82), 0.3), (rgb(177, 47, 82), 0.56),
                          (rgb(122, 28, 72), 0.78), (rgb(58, 18, 52), 1)]), degrees: 172, in: bounds)
    radial(ctx, rgb(58, 16, 64, 0.85), rx: 0.7, ry: 0.6, x: 0.96, y: 1, stop: 0.7)
    radial(ctx, rgb(238, 112, 72, 0.5), rx: 0.58, ry: 0.52, x: 0.6, y: 0.3, stop: 0.72)
    radial(ctx, rgb(255, 190, 120, 0.95), rx: 0.46, ry: 0.74, x: 0.02, y: 0, stop: 0.64)

    // .wall svg: right -6%, bottom -46%, width 70%, rotate(-14deg), opacity .22, faded by mask-image at 200deg.
    let side = 0.7 * width
    let box = CGRect(x: 0.36 * width, y: 1.46 * height - side, width: side, height: side)
    ctx.saveGState()
    ctx.translateBy(x: box.midX, y: box.midY)
    ctx.rotate(by: -14 * .pi / 180)
    ctx.translateBy(x: -box.midX, y: -box.midY)
    ctx.setAlpha(0.22)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.saveGState()
    ctx.translateBy(x: box.minX, y: box.minY)
    ctx.scaleBy(x: side / 824, y: side / 824)
    ctx.translateBy(x: -100, y: -100)
    ctx.setFillColor(rgb(255, 192, 148))
    star(in: ctx)
    ctx.restoreGState()
    ctx.setBlendMode(.destinationIn)
    linear(ctx, gradient([(rgb(0, 0, 0), 0.15), (rgb(0, 0, 0, 0), 0.8)]), degrees: 200, in: box)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Curved arrow over the gap between the two 128 pt icons centred at (160, 190) and (480, 190).
    let from = CGPoint(x: 236, y: 176), control = CGPoint(x: 320, y: 92), to = CGPoint(x: 402, y: 172)
    let angle = atan2(to.y - control.y, to.x - control.x), head: CGFloat = 20, spread: CGFloat = 0.5
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: rgb(58, 16, 52, 0.4))
    ctx.setStrokeColor(rgb(255, 244, 230, 0.95))
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: from)
    ctx.addQuadCurve(to: to, control: control)
    ctx.move(to: CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread)))
    ctx.addLine(to: to)
    ctx.addLine(to: CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread)))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] as [(CGFloat, String)] {
    let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    let dpi = 72 * scale
    CGImageDestinationAddImage(dest, draw(scale: scale),
                               [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(name)") }
}
