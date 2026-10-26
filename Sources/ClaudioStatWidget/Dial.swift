import SwiftUI

// The widgets' rings: session outside, week inside, Fable innermost when it's on. Each ring fills to its limit's percentage, with a hand at the share of
// its window already passed; ring ahead of the hand means faster than an even spread.

/// ClaudioStat's website colors (claudiostatwebsite public/assets/style.css).
enum Brand {
    static let peach = Color(red: 1, green: 0xb2 / 255, blue: 0x66 / 255)
    static let orange = Color(red: 0xee / 255, green: 0x70 / 255, blue: 0x48 / 255)
    static let rose = Color(red: 0xcd / 255, green: 0x3e / 255, blue: 0x48 / 255)
    static let star = Color(red: 1, green: 0xc0 / 255, blue: 0x94 / 255)
    static let cream = Color(red: 1, green: 0xf4 / 255, blue: 0xe6 / 255)
    static let ink = Color(red: 0x1f / 255, green: 0x0d / 255, blue: 0x0b / 255)
    static let night = Color(red: 0x11 / 255, green: 0x0a / 255, blue: 0x0a / 255)
    static let panel = Color(red: 0x1b / 255, green: 0x12 / 255, blue: 0x13 / 255)

    /// Session wears peach to orange (rose would read as too fast's red); week peach; Fable star.
    static func colors(_ key: String) -> [Color] {
        switch key {
        case "s": [peach, orange]
        case "w": [peach]
        default: [star]
        }
    }
}

/// How much of the limit's window has passed, for the hand; nil without a future reset.
func elapsed(_ limit: Limit?, window: Int, now: Int) -> Double? {
    guard let reset = limit?.reset, reset > now else { return nil }
    return min(1, max(0, 1 - Double(reset - now) / Double(window)))
}

struct Meter {
    let fraction: Double
    let hand: Double?
    let colors: [Color]
}

struct Ring: View {
    let meter: Meter
    var width: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let fraction = min(1, max(0, meter.fraction))
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.14), lineWidth: width)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fill(fraction), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                if let hand = meter.hand {
                    Hand(angle: hand, inner: size / 2 - width - 2, outer: size / 2 + 2)
                        .stroke(.primary, style: StrokeStyle(lineWidth: max(1.5, width * 0.28), lineCap: .round))
                }
            }
            .padding(width / 2)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// The gradient runs along the used arc, so a short arc still shows its start colors.
    private func fill(_ fraction: Double) -> AnyShapeStyle {
        guard meter.colors.count > 1 else { return AnyShapeStyle(meter.colors.first ?? .primary) }
        return AnyShapeStyle(AngularGradient(colors: meter.colors, center: .center, startAngle: .zero,
                                             endAngle: .degrees(360 * max(fraction, 0.05))))
    }
}

/// Concentric rings, the first outermost, then pace's open ring when given.
struct Rings: View {
    let meters: [Meter]
    var pace: Meter? = nil
    /// The ring width as a share of the size.
    var thickness: CGFloat = 0.085

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            // More rings get thinner, so the middle keeps room for the number (a quarter of the size, at least).
            let rings = CGFloat(meters.count + (pace == nil ? 0 : 1))
            let width = min(size * thickness, size * 0.27 / (rings * 1.32 - 0.32))
            ZStack {
                ForEach(Array(meters.enumerated()), id: \.offset) { index, meter in
                    Ring(meter: meter, width: width)
                        .padding(CGFloat(index) * width * 1.32)
                }
                if let pace {
                    Gauge(meter: pace, width: width)
                        .padding(CGFloat(meters.count) * width * 1.32)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct Hand: Shape {
    let angle: Double
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = (angle * 360 - 90) * .pi / 180
        var path = Path()
        path.move(to: CGPoint(x: center.x + inner * cos(radians), y: center.y + inner * sin(radians)))
        path.addLine(to: CGPoint(x: center.x + outer * cos(radians), y: center.y + outer * sin(radians)))
        return path
    }
}

/// The bar form of the same thing: a track, the fill in the limit's colors, and the hand as a short upright mark.
struct Bar: View {
    let meter: Meter
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: meter.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(1, max(0, meter.fraction)))
                    .widgetAccentable()
                if let hand = meter.hand {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: height + 6)
                        .offset(x: geo.size.width * hand - 1)
                }
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
    }
}

/// Three quarters of a ring, open at the top: pace fills it clockwise like the limits, the budget is the mark.
/// Rings draws it innermost.
struct Gauge: View {
    let meter: Meter
    var width: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let fraction = min(1, max(0, meter.fraction))
            // The round ends add half a width each: the drawn length counts them, so a fifth looks like a fifth.
            let circumference = .pi * (size - width)
            let seen = 0.75 * circumference + width
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.primary.opacity(0.14), style: StrokeStyle(lineWidth: width, lineCap: .round))
                if fraction > 0 {
                    Circle()
                        .trim(from: 0, to: max(0.001, fraction * seen - width) / circumference)
                        .stroke(meter.colors.first ?? .primary, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .widgetAccentable()
                }
                if let mark = meter.hand {
                    // Hand counts from 12 o'clock; the arc starts a quarter turn later, before the 315° turn below.
                    let at = (mark * seen - width / 2) / (0.75 * circumference)
                    Hand(angle: (270 * at + 90) / 360, inner: size / 2 - width - 2, outer: size / 2 + 2)
                        .stroke(.primary, style: StrokeStyle(lineWidth: max(1.5, width * 0.28), lineCap: .round))
                }
            }
            .rotationEffect(.degrees(315))
            .padding(width / 2)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
