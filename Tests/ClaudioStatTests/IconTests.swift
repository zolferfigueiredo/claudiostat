import AppKit
import Testing
@testable import ClaudioStat

// The untinted star and the warning triangle are not templates, yet black on a light menu bar and white on a dark one.
@Test func menuBarIconsFollowTheMenuBar() {
    let triangle = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!
    for icon in [star(nil), redrawn(triangle, lift: 1.5)!, redrawn(star(nil), alpha: 0.7)!] {
        #expect(!icon.isTemplate)
        #expect(ink(icon, .aqua) < 0.5 && ink(icon, .darkAqua) > 0.5)
    }
}

// The colour of the icon's most opaque pixel, drawn under `appearance`.
private func ink(_ icon: NSImage, _ appearance: NSAppearance.Name) -> CGFloat {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(icon.size.width), pixelsHigh: Int(icon.size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { icon.draw(at: .zero, from: .zero, operation: .copy, fraction: 1) }
    NSGraphicsContext.current = nil
    let pixels = (0..<rep.pixelsHigh).flatMap { y in (0..<rep.pixelsWide).map { x in rep.colorAt(x: x, y: y)! } }
    return pixels.max { $0.alphaComponent < $1.alphaComponent }!.redComponent
}
