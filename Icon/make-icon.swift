// App icon: a slightly tilted five-ray star in white cream on a Claude orange gradient.
// build.sh runs this: swift Icon/make-icon.swift <output.iconset>
import AppKit

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // macOS icon grid: an 824-unit rounded square centred in 1024, lighter at the top left.
    let background = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                                  xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 212 / 255, green: 124 / 255, blue: 90 / 255, alpha: 1),
               ending: NSColor(srgbRed: 150 / 255, green: 76 / 255, blue: 54 / 255, alpha: 1))!
        .draw(in: background, angle: -60)

    // Each ray is the hull of a hub circle and a small tip circle, so it tapers to a near point.
    NSColor(srgbRed: 250 / 255, green: 243 / 255, blue: 232 / 255, alpha: 1).setFill()
    let hubRadius = 44 * s, tipRadius = 9 * s, length = 235 * s
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
        let side = NSBezierPath()
        side.move(to: point(hub, hubRadius, angle + .pi / 2 + spread))
        side.line(to: point(tip, tipRadius, angle + .pi / 2 + spread))
        side.line(to: point(tip, tipRadius, angle - .pi / 2 - spread))
        side.line(to: point(hub, hubRadius, angle - .pi / 2 - spread))
        side.close()
        side.fill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - tipRadius, y: tip.y - tipRadius, width: 2 * tipRadius, height: 2 * tipRadius)).fill()
    }
    NSBezierPath(ovalIn: NSRect(x: hub.x - hubRadius, y: hub.y - hubRadius, width: 2 * hubRadius, height: 2 * hubRadius)).fill()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(pixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(pixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
