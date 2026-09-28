// App icon: a slightly tilted five-ray star with a cream-to-peach gradient on a bright orange gradient.
// build.sh runs this: swift Icon/make-icon.swift <output.iconset>
import AppKit

// Soft bevel: light glows in from the top edges and shade from the bottom ones, so the shape looks rounded.
// Each glow is the blurred shadow of everything outside the shape, clipped to the shape. The caster is drawn
// far off-canvas and only its shadow is shifted back, so no hard fill lands on the anti-aliased edge.
func bevel(_ path: NSBezierPath, light: NSColor, dark: NSColor, blur: CGFloat, offset: CGFloat) {
    let away: CGFloat = 100_000
    for (color, dy) in [(dark, offset), (light, -offset)] {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let outside = NSBezierPath(rect: path.bounds.insetBy(dx: -4 * (blur + offset), dy: -4 * (blur + offset)))
        outside.append(path)
        outside.windingRule = .evenOdd
        outside.transform(using: AffineTransform(translationByX: away, byY: 0))
        let glow = NSShadow()
        glow.shadowColor = color
        glow.shadowOffset = NSSize(width: -away, height: dy)
        glow.shadowBlurRadius = blur
        glow.set()
        outside.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // macOS icon grid: an 824-unit rounded square centred in 1024, lighter at the top left.
    let background = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                                  xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(srgbRed: 255 / 255, green: 178 / 255, blue: 102 / 255, alpha: 1),
                        NSColor(srgbRed: 238 / 255, green: 112 / 255, blue: 72 / 255, alpha: 1),
                        NSColor(srgbRed: 205 / 255, green: 62 / 255, blue: 72 / 255, alpha: 1)])!
        .draw(in: background, angle: -60)
    // Soft glow behind the star.
    NSGradient(starting: NSColor(white: 1, alpha: 0.15), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: background, relativeCenterPosition: .zero)
    bevel(background, light: NSColor(white: 1, alpha: 0.45),
          dark: NSColor(srgbRed: 120 / 255, green: 20 / 255, blue: 40 / 255, alpha: 0.35), blur: 40 * s, offset: 14 * s)

    // Each ray is the hull of a hub circle and a small tip circle, so it tapers to a near point.
    // All pieces wind the same way so the non-zero union of the combined path is the whole star.
    var star = NSBezierPath()
    let hubRadius = 66 * s, tipRadius = 14 * s, length = 245 * s
    let tilt = -14 * CGFloat.pi / 180
    let angles = (0..<5).map { CGFloat.pi / 2 + tilt + CGFloat($0) * 2 * .pi / 5 }
    // Centre the star's bounding box, not its hub: five rays reach further on one side than the other.
    let xs = angles.map { cos($0) * length }, ys = angles.map { sin($0) * length }
    let hub = NSPoint(x: 512 * s - (xs.max()! + xs.min()!) / 2, y: 512 * s - (ys.max()! + ys.min()!) / 2)
    let spread = asin((hubRadius - tipRadius) / length)
    func point(_ centre: NSPoint, _ radius: CGFloat, _ angle: CGFloat) -> NSPoint {
        NSPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    }
    for angle in angles {
        let tip = point(hub, length, angle)
        star.move(to: point(hub, hubRadius, angle - .pi / 2 - spread))
        star.line(to: point(tip, tipRadius, angle - .pi / 2 - spread))
        star.line(to: point(tip, tipRadius, angle + .pi / 2 + spread))
        star.line(to: point(hub, hubRadius, angle + .pi / 2 + spread))
        star.close()
        star.appendOval(in: NSRect(x: tip.x - tipRadius, y: tip.y - tipRadius, width: 2 * tipRadius, height: 2 * tipRadius))
    }
    star.appendOval(in: NSRect(x: hub.x - hubRadius, y: hub.y - hubRadius, width: 2 * hubRadius, height: 2 * hubRadius))
    // Merge the pieces into one outline so the bevel only follows the star's outer edge.
    star = NSBezierPath(cgPath: star.cgPath.normalized())

    // A faint soft shadow so the star sits just above the background.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowColor = NSColor(srgbRed: 120 / 255, green: 30 / 255, blue: 30 / 255, alpha: 0.2)
    shadow.set()
    star.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(srgbRed: 255 / 255, green: 244 / 255, blue: 230 / 255, alpha: 1),
               ending: NSColor(srgbRed: 255 / 255, green: 192 / 255, blue: 148 / 255, alpha: 1))!
        .draw(in: star, angle: -70)
    bevel(star, light: NSColor(white: 1, alpha: 1),
          dark: NSColor(srgbRed: 214 / 255, green: 110 / 255, blue: 80 / 255, alpha: 0.6), blur: 12 * s, offset: 7 * s)

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(pixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(pixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
