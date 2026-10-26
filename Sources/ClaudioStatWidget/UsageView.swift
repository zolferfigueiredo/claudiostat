import ClaudioStatStrings
import SwiftUI
import WidgetKit

// The timeline and views of the desktop widgets. Every one of them shows session and week at least.

struct Entry: TimelineEntry {
    let date: Date
    let reply: Reply?
    let settings: Settings
    let config: UsageConfig
    let kind: Kind
}

struct Provider: AppIntentTimelineProvider {
    /// What this widget shows (Kind).
    var kind = RingsAll.kind

    /// The app's settings, with P and B both on when this widget is one that shows them.
    private var settings: Settings {
        var settings = Settings.current
        if kind.rates { (settings.showPace, settings.showBudget) = (true, true) }
        return settings
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, reply: .sample, settings: Settings(), config: UsageConfig(), kind: kind)
    }

    func snapshot(for configuration: UsageConfig, in context: Context) async -> Entry {
        Settings.current.speak()
        // The gallery shows sample numbers with every limit used, so each kind looks like what it shows (real numbers
        // at 0% Fable would make the kinds with Fable look like the ones without).
        return Entry(date: .now, reply: context.isPreview ? .sample : cachedReply(configuration.stored), settings: settings,
              config: configuration, kind: kind)
    }

    func timeline(for configuration: UsageConfig, in context: Context) async -> Timeline<Entry> {
        let settings = settings
        settings.speak()
        let reply = cachedReply(configuration.stored)
        // Entries 5 min apart keep the hands, countdowns, the stale look and pace colors moving without spending the
        // reload budget.
        let entries = (0...12).map {
            Entry(date: .now.addingTimeInterval(Double($0) * 300), reply: reply, settings: settings, config: configuration,
                  kind: kind)
        }
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

extension Reply {
    /// For the widget gallery and placeholders: a session going fast, a quiet week.
    static var sample: Reply {
        let now = Int(Date().timeIntervalSince1970)
        return Reply(snap: Snap(src: "app", s: Limit(pct: 64, reset: now + 7800, locked: nil, severity: nil),
                                w: Limit(pct: 41, reset: now + 367_200, locked: nil, severity: nil),
                                f: Limit(pct: 12, reset: now + 367_200, locked: nil, severity: nil)),
                     checkedAt: now, speed: Speeds(s: 20, w: 0.3), loginNeeded: nil)
    }
}

extension Pace {
    /// ClaudioStat's orange and increased-contrast red.
    var color: Color? {
        switch self {
        case .ok: nil
        case .fast: Color(red: 1, green: 0x92 / 255, blue: 0x30 / 255)
        case .tooFast: Color(red: 1, green: 0x69 / 255, blue: 0x61 / 255)
        }
    }
}

/// One limit as a widget shows it.
struct Shown: Identifiable {
    let kind: LimitChoice
    let limit: Limit
    let pace: Pace

    var id: LimitChoice { kind }
    var name: String { tr(kind.rawValue) }
    /// The number's color: pace, or red once the limit is used up.
    var tint: Color { limit.locked == true ? Pace.tooFast.color! : pace.color ?? .primary }
    /// A lock once the limit is used up; pace shows in color only.
    var symbol: String? { limit.locked == true ? "lock.fill" : nil }
    var window: Int { kind == .session ? 5 * 3600 : 7 * 86400 }
    var colors: [Color] { Brand.colors(kind == .session ? "s" : kind == .week ? "w" : "f") }

    func meter(now: Int) -> Meter {
        Meter(fraction: Double(usedNow(limit, now: now)) / 100, hand: elapsed(limit, window: window, now: now), colors: colors)
    }
}

/// P against B as one meter: P fills it in the week's pace color, B is the mark in the middle.
func paceMeter(_ r: Rates, _ settings: Settings) -> Meter {
    let scale = paceScale(settings.showPace ? r.p : nil, settings.showBudget ? r.b : nil)
    return Meter(fraction: scale.fraction, hand: scale.mark, colors: [r.w.color ?? Brand.peach])
}

/// Session and week, then Fable once it's used (1% or more); limits the reply doesn't have are left out.
func shown(_ reply: Reply, _ r: Rates) -> [Shown] {
    let used = (reply.snap.f?.pct ?? 0) > 0
    let fable = used ? reply.snap.f : nil
    let all: [(LimitChoice, Limit?, Pace)] = [(.session, reply.snap.s, r.s), (.week, reply.snap.w, r.w), (.fable, fable, .ok)]
    return all.compactMap { kind, limit, pace in limit.map { Shown(kind: kind, limit: $0, pace: pace) } }
}

/// The limit whose number is large in the middle of the rings: the widget's focus. Focus never moves a limit:
/// session, week, then Fable, always.
func mainItem(_ items: [Shown], _ config: UsageConfig) -> Shown? {
    items.first { $0.kind == config.focus } ?? items.first
}

extension View {
    /// The widget's theme: the desktop's light or dark, or always one of them.
    @ViewBuilder func themed(_ theme: ThemeChoice?) -> some View {
        switch theme {
        case .dark: environment(\.colorScheme, .dark)
        case .light: environment(\.colorScheme, .light)
        default: self
        }
    }
}

/// The website's night with its rose glow, or cream by day.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            scheme == .dark ? Brand.night : Brand.cream
            RadialGradient(colors: [(scheme == .dark ? Brand.rose : Brand.orange).opacity(scheme == .dark ? 0.4 : 0.22), .clear],
                           center: .top, startRadius: 0, endRadius: 190)
        }
    }
}

struct UsageView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var now: Int { Int(entry.date.timeIntervalSince1970) }
    private var stale: Bool { entry.reply.map { now - $0.checkedAt > staleAfter } ?? false }

    var body: some View {
        content
            .opacity(stale ? 0.8 : 1)
            .themed(entry.config.theme)
            .containerBackground(for: .widget) {
                Backdrop().themed(entry.config.theme)
            }
    }

    @ViewBuilder private var content: some View {
        let reply = entry.reply
        let r = reply.map { rates($0, entry.settings, now: now) }
        let items = reply.flatMap { reply in r.map { shown(reply, $0) } } ?? []
        if let reply, let r, let main = mainItem(items, entry.config) {
            switch family {
            case .systemSmall:
                entry.kind.style == .bars ? AnyView(barRows(items, r)) : AnyView(dial(items, main, r))
            default:
                medium(items, main, reply, r)
            }
        } else {
            empty
        }
    }

    /// The rings with the large number, its name, and the next limit's number under it.
    private func dial(_ items: [Shown], _ main: Shown, _ r: Rates) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let crowded = items.count + (innerPace(r) == nil ? 0 : 1) > 2
            ZStack {
                Rings(meters: items.map { $0.meter(now: now) }, pace: innerPace(r), thickness: crowded ? 0.075 : 0.085)
                VStack(spacing: 0) {
                    Text(percentText(main.limit, now: now))
                        .font(.system(size: size * (crowded ? 0.15 : 0.2), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(main.tint)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    label(main, size: size * (crowded ? 0.055 : 0.065)).minimumScaleFactor(0.6)
                    // P and B in the middle too: numbers, not rings.
                    if entry.kind.rates {
                        HStack(spacing: size * 0.04) {
                            Text(verbatim: "P \(rateText(r.p))").foregroundStyle(r.w.color ?? .primary)
                            Text(verbatim: "B \(rateText(r.b))")
                        }
                        .font(.system(size: size * (crowded ? 0.05 : 0.06), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.top, size * 0.02)
                    }
                }
                .padding(.horizontal, size * (crowded ? 0.33 : 0.24))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(items, r))
    }

    @ViewBuilder private func medium(_ items: [Shown], _ main: Shown, _ reply: Reply, _ r: Rates) -> some View {
        if entry.kind.style == .bars {
            VStack(alignment: .leading, spacing: 6) {
                barRows(items, r, columns: true)
                Spacer(minLength: 0)
                footer(reply)
            }
        } else {
            HStack(spacing: 14) {
                dial(items, main, r).aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 6) {
                    if let warning = warning(reply.snap) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Pace.tooFast.color!)
                            .lineLimit(1)
                    }
                    let pace = paceRates(r)
                    let tight = items.count + (pace == nil ? 0 : 1) > 3
                    ForEach(items) { row($0, tight: tight) }
                    if let pace { paceRow(pace, tight: tight) }
                    Spacer(minLength: 0)
                    footer(reply)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A dot in the limit's color, its name and reset, and its number.
    private func row(_ item: Shown, tight: Bool) -> some View {
        let name = HStack(spacing: 3) {
            Text(item.name).font(.subheadline.weight(.semibold))
            if let symbol = item.symbol { Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(item.tint) }
        }
        return listRow(item.colors.count > 1 ? item.colors[1] : item.colors[0], name,
                       detail: item.limit.reset.flatMap { $0 > now ? span($0 - now) : nil },
                       value: percentText(item.limit, now: now), tint: item.tint, tight: tight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(item))
    }

    /// Pace as one more limit in the list: P's number, B where a limit shows its reset.
    private func paceRow(_ r: Rates, tight: Bool) -> some View {
        let settings = entry.settings
        let unit = rateUnit(settings)
        return listRow(r.w.color ?? Brand.peach, Text(tr("pace")).font(.subheadline.weight(.semibold)),
                       // Four lines leave room for B's letter only, as in the bar widgets.
                       detail: tight ? "B \(rateText(r.b))" : "\(tr("budget")) \(rateText(r.b))\(unit)",
                       value: rateText(r.p) + unit,
                       tint: r.w.color ?? .primary, tight: tight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenRates(r, settings))
    }

    /// One line of the list beside the rings: a dot in its color, its name and detail, its number. With four lines,
    /// the detail sits beside the name so they fit.
    private func listRow(_ color: Color, _ name: some View, detail: String?, value: String, tint: Color,
                         tight: Bool) -> some View {
        // The gray detail goes, not gets cut, when the line has no room for it; the name and number never shrink.
        ViewThatFits(in: .horizontal) {
            listLine(color, name, detail: detail, value: value, tint: tint, tight: tight)
            listLine(color, name, detail: nil, value: value, tint: tint, tight: tight)
        }
    }

    private func listLine(_ color: Color, _ name: some View, detail: String?, value: String, tint: Color,
                          tight: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            if tight {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    name
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    name
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .lineLimit(1)
    }

    /// The bars: every limit, then pace, all in the same pattern. In a medium widget, three bars run full width and four
    /// take two columns.
    @ViewBuilder private func barRows(_ items: [Shown], _ r: Rates, columns: Bool = false) -> some View {
        let rows = items.map { AnyView(limitBar($0)) } + (paceRates(r).map { [AnyView(paceBar($0))] } ?? [])
        if columns, rows.count > 3 {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(0..<(rows.count + 1) / 2, id: \.self) { line in
                    GridRow {
                        rows[line * 2]
                        if line * 2 + 1 < rows.count { rows[line * 2 + 1] } else { Color.clear.gridCellUnsizedAxes(.vertical) }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: rows.count > 3 ? 4 : 8) {
                ForEach(rows.indices, id: \.self) { rows[$0] }
            }
        }
    }

    private func limitBar(_ item: Shown) -> some View {
        let reset = item.limit.reset.flatMap { $0 > now ? span($0 - now) : nil }
        return barRow(label(item, size: 11), detail: reset, value: percentText(item.limit, now: now),
                      tint: item.tint, meter: item.meter(now: now))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(item))
    }

    /// Pace as one more limit: P fills the bar, B is the mark, B's number where a limit shows its reset.
    private func paceBar(_ r: Rates) -> some View {
        let settings = entry.settings
        let unit = rateUnit(settings)
        return barRow(caps(tr("pace"), size: 11), detail: "B \(rateText(r.b))\(unit)", value: rateText(r.p) + unit,
                      tint: r.w.color ?? .primary, meter: paceMeter(r, settings))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenRates(r, settings))
    }

    /// One bar row: name, detail and number over the bar.
    private func barRow(_ name: some View, detail: String?, value: String, tint: Color, meter: Meter) -> some View {
        let number = Text(value)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
        return VStack(alignment: .leading, spacing: 2) {
            // As beside the rings: the gray detail goes before anything gets cut.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer(minLength: 4)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                    number
                }
                HStack(alignment: .firstTextBaseline) { name; Spacer(minLength: 4); number }
            }
            .lineLimit(1)
            Bar(meter: meter, height: 6)
        }
    }

    private func innerPace(_ r: Rates) -> Meter? {
        paceRates(r).map { paceMeter($0, entry.settings) }
    }

    private func spoken(_ items: [Shown], _ r: Rates) -> String {
        (items.map(spoken) + [paceRates(r).map { spokenRates($0, entry.settings) }].compactMap { $0 }).joined(separator: ". ")
    }

    /// P and B to draw, when this widget shows them.
    private func paceRates(_ r: Rates) -> Rates? {
        entry.kind.rates ? r : nil
    }

    /// The login warning and how old the numbers are.
    private func footer(_ reply: Reply) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if reply.loginNeeded == true { loginAgain }
            Text(updated(reply))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var loginAgain: some View {
        Text(tr("signed_out")).font(.caption2.weight(.semibold)).foregroundStyle(Pace.tooFast.color!)
    }

    /// How old the numbers are, after the account's name once there are several.
    private func updated(_ reply: Reply) -> String {
        let age = now - reply.checkedAt
        let updated = age < 60 ? tr("updated_now") : tr("updated_ago", ["time": span(age)])
        return accountName.map { "\($0) · \(updated)" } ?? updated
    }

    /// Which profile, once there are several.
    private var accountName: String? {
        guard storedAccounts().count > 1 else { return nil }
        return entry.config.stored?.label
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Rings(meters: [Meter(fraction: 0, hand: nil, colors: Brand.colors("s")),
                           Meter(fraction: 0, hand: nil, colors: Brand.colors("w"))])
                .frame(maxWidth: 64, maxHeight: 64)
            Text(tr(storedAccounts().isEmpty ? "add_a_profile" : "updating")).font(.caption).multilineTextAlignment(.center)
        }
    }

    // MARK: Pieces

    private func caps(_ text: String, size: CGFloat) -> some View {
        Text(text.uppercased())
            .tracking(size * 0.08)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The limit's name, with a lock once it's used up.
    private func label(_ item: Shown, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text(item.name.uppercased())
                .tracking(size * 0.08)
            if let symbol = item.symbol {
                Image(systemName: symbol).foregroundStyle(item.tint)
            }
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func spoken(_ item: Shown) -> String {
        let used = "\(item.name) \(percentText(item.limit, now: now))"
        var text = item.limit.reset.flatMap { $0 > now ? tr("resets", ["limit": used, "time": span($0 - now)]) : nil } ?? used
        switch item.pace {
        case .fast: text += ", " + tr("going_fast")
        case .tooFast: text += ", " + tr("going_too_fast")
        case .ok: break
        }
        return text
    }
}
