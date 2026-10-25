// Copied from appclaudiostat's apps/mobile/targets/_shared for the desktop widget: copy it again when it changes there. Changed here: the small size on the Mac too, and no lock screen sizes there.
import SwiftUI
import WidgetKit

// The timeline and views behind the iPhone widgets (home and lock screen) and the watch complications. Every one of
// them shows session and week at least.

@available(iOS 17.0, watchOS 10.0, *)
struct Entry: TimelineEntry {
    let date: Date
    let reply: Reply?
    let settings: Settings
    let config: UsageConfig
    let kind: Kind
}

@available(iOS 17.0, watchOS 10.0, *)
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
        // The gallery and the watch's list show sample numbers with every limit used, so each kind looks like what it
        // shows (real numbers at 0% Fable would make the kinds with Fable look like the ones without).
        Entry(date: .now, reply: context.isPreview ? .sample : cachedReply(configuration.stored), settings: settings,
              config: configuration, kind: kind)
    }

    func timeline(for configuration: UsageConfig, in context: Context) async -> Timeline<Entry> {
        let settings = settings
        let account = configuration.stored
        let reply = await withCheckedContinuation { done in fetchReply(account) { done.resume(returning: $0) } }
            ?? cachedReply(account)
        // Entries 5 min apart keep the hands, countdowns, the stale look and pace colors moving without spending the
        // reload budget.
        let entries = (0...12).map {
            Entry(date: .now.addingTimeInterval(Double($0) * 300), reply: reply, settings: settings, config: configuration,
                  kind: kind)
        }
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    #if os(watchOS)
    /// Watch faces can't edit a widget's choices, so these are the ones they offer, each named for what it draws.
    func recommendations() -> [AppIntentRecommendation<UsageConfig>] {
        let accounts = AccountEntity.all()
        // One entry per kind, named for what it shows; the app's focus picks the middle number. Several accounts: one
        // entry per account.
        guard accounts.count > 1 else { return [AppIntentRecommendation(intent: UsageConfig(), description: kind.description)] }
        let shows = String(localized: kind.description)
        return accounts.map { AppIntentRecommendation(intent: UsageConfig(account: $0), description: "\($0.name): \(shows)") }
    }
    #endif
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
@available(iOS 17.0, watchOS 10.0, *)
struct Shown: Identifiable {
    let kind: LimitChoice
    let limit: Limit
    let pace: Pace

    var id: LimitChoice { kind }
    var name: String { kind.title }
    var letter: String { String(name.prefix(1)) }
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

@available(iOS 17.0, watchOS 10.0, *)
extension LimitChoice {
    var title: String {
        switch self {
        case .session: String(localized: "Session")
        case .week: String(localized: "Week")
        case .fable: String(localized: "Fable")
        }
    }
}

/// Session and week, then Fable once it's used (1% or more; the status line doesn't report it); limits the reply
/// doesn't have are left out.
@available(iOS 17.0, watchOS 10.0, *)
func shown(_ reply: Reply, _ r: Rates) -> [Shown] {
    let used = (reply.snap.f?.pct ?? 0) > 0
    let fable = reply.snap.src == "sl" || !used ? nil : reply.snap.f
    let all: [(LimitChoice, Limit?, Pace)] = [(.session, reply.snap.s, r.s), (.week, reply.snap.w, r.w), (.fable, fable, .ok)]
    return all.compactMap { kind, limit, pace in limit.map { Shown(kind: kind, limit: $0, pace: pace) } }
}

/// The limit whose number is large in the middle of the rings: the widget's focus, else the app's. Focus never moves
/// a limit: session, week, then Fable, always.
@available(iOS 17.0, watchOS 10.0, *)
func mainItem(_ items: [Shown], _ config: UsageConfig, _ settings: Settings) -> Shown? {
    let focus = config.focus(settings)
    return items.first { $0.kind == focus } ?? items.first
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

@available(iOS 17.0, watchOS 10.0, *)
struct UsageView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var now: Int { Int(entry.date.timeIntervalSince1970) }
    private var stale: Bool { entry.reply.map { now - $0.checkedAt > staleAfter } ?? false }
    private var accessory: Bool {
        #if os(watchOS)
        true
        #elseif os(macOS)
        false
        #else
        [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
        #endif
    }

    var body: some View {
        content
            .opacity(stale ? 0.8 : 1)
            .containerBackground(for: .widget) {
                if accessory { Color.clear } else { Backdrop() }
            }
    }

    @ViewBuilder private var content: some View {
        let reply = entry.reply
        let r = reply.map { rates($0, entry.settings, now: now) }
        let items = reply.flatMap { reply in r.map { shown(reply, $0) } } ?? []
        if let reply, let r, let main = mainItem(items, entry.config, entry.settings) {
            switch family {
            #if !os(macOS)
            case .accessoryInline:
                inline(items, r)
            case .accessoryCircular:
                entry.kind.style == .bars ? AnyView(tinyBars(items, r)) : AnyView(circular(items, main, r))
            case .accessoryRectangular:
                entry.kind.style == .bars ? AnyView(barRows(items, r, compact: true)) : AnyView(rectangular(items, r))
            #endif
            #if os(iOS) || os(macOS)
            case .systemSmall:
                entry.kind.style == .bars ? AnyView(barRows(items, r, compact: false)) : AnyView(dial(items, main, r))
            #endif
            default:
                medium(items, main, reply, r)
            }
        } else {
            empty
        }
    }

    // MARK: Lock screen and watch

    /// The limits as rings, pace inside them, the large number in the middle.
    private func circular(_ items: [Shown], _ main: Shown, _ r: Rates) -> some View {
        ZStack {
            Rings(meters: items.map { $0.meter(now: now) }, pace: innerPace(r), thickness: 0.07)
            VStack(spacing: -1) {
                label(main, size: 8)
                Text(percentText(main.limit, now: now).replacingOccurrences(of: "%", with: ""))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(items, r))
    }

    private func inline(_ items: [Shown], _ r: Rates) -> some View {
        let pace = paceRates(r).map { ["P \(rateText($0.p))"] } ?? []
        let text = (items.map { "\($0.letter) \(percentText($0.limit, now: now))" } + pace).joined(separator: "  ")
        return Label(text, systemImage: "gauge.with.dots.needle.50percent")
    }

    /// The rings (pace inside) beside one line per limit, and P.
    private func rectangular(_ items: [Shown], _ r: Rates) -> some View {
        HStack(spacing: 6) {
            Rings(meters: items.map { $0.meter(now: now) }, pace: innerPace(r), thickness: 0.09)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    line(label(item, size: 10), value: percentText(item.limit, now: now), tint: .primary,
                         detail: item.limit.reset.flatMap { $0 > now ? span($0 - now) : nil })
                }
                if paceRates(r) != nil {
                    let settings = entry.settings
                    line(caps(settings.showPace ? "P" : "B", size: 10),
                         value: rateText(settings.showPace ? r.p : r.b) + rateUnit(settings),
                         tint: settings.showPace ? r.w.color ?? .primary : .primary,
                         detail: settings.showPace && settings.showBudget ? "B \(rateText(r.b))" : nil,
                         short: rateText(settings.showPace ? r.p : r.b))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(items, r))
    }

    /// One line beside the rings: same sizes on every line. When it doesn't fit, the number first drops its unit
    /// (`short`, so B stays beside P), then the gray detail goes; nothing gets cut.
    private func line(_ name: some View, value: String, tint: Color, detail: String?, short: String? = nil) -> some View {
        let number = { (text: String) in
            Text(text).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
        let gray = detail.map { Text($0).font(.system(size: 10)).foregroundStyle(.secondary) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { name; number(value); gray }
            HStack(spacing: 4) { name; number(short ?? value); gray }
            HStack(spacing: 4) { name; number(value) }
        }
        .lineLimit(1)
    }

    /// The 1x1 bars: letter, bar and number per limit, then pace, numbers lined up and never cut. No pace arrow and
    /// no % sign (as in the rings' middle): the 1x1 has no room; the bar's mark shows the pace.
    private func tinyBars(_ items: [Shown], _ r: Rates) -> some View {
        let pace = paceRates(r).map { [("P", paceMeter($0, entry.settings), rateText($0.p), $0.w.color ?? Color.primary)] } ?? []
        let rows = items.map { ($0.letter, $0.meter(now: now), percentText($0.limit, now: now), $0.tint) } + pace
        return Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 1) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    Text(rows[index].0).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Bar(meter: rows[index].1, height: 4)
                    Text(rows[index].2.replacingOccurrences(of: "%", with: ""))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rows[index].3)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(items, r))
    }

    // MARK: Home screen

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
                            Text("P \(rateText(r.p))").foregroundStyle(r.w.color ?? .primary)
                            Text("B \(rateText(r.b))")
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
                barRows(items, r, compact: false, columns: true)
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
        return listRow(r.w.color ?? Brand.peach, Text(String(localized: "Pace")).font(.subheadline.weight(.semibold)),
                       // Four lines leave room for B's letter only, as in the bar widgets.
                       detail: tight ? "B \(rateText(r.b))" : String(localized: "Budget \(rateText(r.b))\(unit)"),
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
    @ViewBuilder private func barRows(_ items: [Shown], _ r: Rates, compact: Bool, columns: Bool = false) -> some View {
        let rows = items.map { AnyView(limitBar($0, compact: compact)) } + (paceRates(r).map { [AnyView(paceBar($0, compact: compact))] } ?? [])
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
            VStack(alignment: .leading, spacing: compact ? 2 : rows.count > 3 ? 4 : 8) {
                ForEach(rows.indices, id: \.self) { rows[$0] }
            }
        }
    }

    private func limitBar(_ item: Shown, compact: Bool) -> some View {
        let reset = item.limit.reset.flatMap { $0 > now ? span($0 - now) : nil }
        return barRow(label(item, size: compact ? 10 : 11), detail: reset, value: percentText(item.limit, now: now),
                      tint: item.tint, meter: item.meter(now: now), compact: compact)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(item))
    }

    /// Pace as one more limit: P fills the bar, B is the mark, B's number where a limit shows its reset.
    private func paceBar(_ r: Rates, compact: Bool) -> some View {
        let settings = entry.settings
        let unit = rateUnit(settings)
        return barRow(caps(accessory ? "P" : String(localized: "Pace"), size: compact ? 10 : 11),
                      detail: "B \(rateText(r.b))\(unit)", value: rateText(r.p) + (compact ? "" : unit),
                      tint: r.w.color ?? .primary, meter: paceMeter(r, settings), compact: compact)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenRates(r, settings))
    }

    /// One bar row: name, detail and number over the bar; on the lock screen and the watch, all on one line.
    @ViewBuilder private func barRow(_ name: some View, detail: String?, value: String, tint: Color, meter: Meter,
                                     compact: Bool) -> some View {
        let number = Text(value)
            .font(.system(size: compact ? 12 : 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
        if compact {
            HStack(spacing: 4) {
                name
                Bar(meter: meter, height: 4)
                number
            }
            .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 2) {
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
        Text("Log in again in ClaudioStat").font(.caption2.weight(.semibold)).foregroundStyle(Pace.tooFast.color!)
    }

    /// How old the numbers are, after the account's name once there are several.
    private func updated(_ reply: Reply) -> String {
        let age = now - reply.checkedAt
        let updated = age < 60 ? String(localized: "Updated just now") : String(localized: "Updated \(span(age)) ago")
        return accountName.map { "\($0) · \(updated)" } ?? updated
    }

    /// Which account, once there are several.
    private var accountName: String? {
        let accounts = storedAccounts()
        guard accounts.count > 1, let stored = entry.config.stored, let index = accounts.firstIndex(of: stored) else { return nil }
        return stored.label(index)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Rings(meters: [Meter(fraction: 0, hand: nil, colors: Brand.colors("s")),
                           Meter(fraction: 0, hand: nil, colors: Brand.colors("w"))])
                .frame(maxWidth: 64, maxHeight: 64)
            #if os(macOS)
            Text("Open ClaudioStat to log in").font(.caption).multilineTextAlignment(.center)
            #else
            if family != .accessoryCircular {
                Text("Open ClaudioStat to log in").font(.caption).multilineTextAlignment(.center)
            }
            #endif
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

    /// The limit's name (a letter on the lock screen), with the pace in shape when it's fast.
    private func label(_ item: Shown, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text(accessory ? item.letter : item.name.uppercased())
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
        var text = "\(item.name) \(percentText(item.limit, now: now))"
        if let reset = item.limit.reset, reset > now { text += ", " + String(localized: "resets in \(span(reset - now))") }
        switch item.pace {
        case .fast: text += ", " + String(localized: "going fast")
        case .tooFast: text += ", " + String(localized: "going too fast")
        case .ok: break
        }
        return text
    }
}
