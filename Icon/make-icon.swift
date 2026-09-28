// App icon: a five-ray star in a creamy Claude orange on a darker tone of the same orange.
// build.sh runs this: swift Icon/make-icon.swift <output.iconset>
import AppKit

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // macOS icon grid: an 824-unit rounded square centred in 1024.
    NSColor(srgbRed: 184 / 255, green: 101 / 255, blue: 74 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                 xRadius: 185 * s, yRadius: 185 * s).fill()

    // Each ray is the hull of a hub circle and a smaller tip circle. The centre sits a little low
    // because a five-ray star with one ray up reaches higher than it reaches down.
    NSColor(srgbRed: 238 / 255, green: 178 / 255, blue: 150 / 255, alpha: 1).setFill()
    let hub = NSPoint(x: 512 * s, y: 486 * s), hubRadius = 64 * s, tipRadius = 38 * s, length = 285 * s
    let spread = asin((hubRadius - tipRadius) / length)
    func point(_ centre: NSPoint, _ radius: CGFloat, _ angle: CGFloat) -> NSPoint {
        NSPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    }
    for ray in 0..<5 {
        let angle = CGFloat.pi / 2 + CGFloat(ray) * 2 * .pi / 5
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
