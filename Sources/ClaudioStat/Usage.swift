import AppKit

nonisolated struct Limit: Equatable, Codable {
    var percent: Int
    var resetsAt: Date?
    var locked = false
    var severity: String?    // nil when Claude Code left out its limits list: unknown, not normal
}

nonisolated struct Usage: Equatable, Codable {
    var session: Limit?
    var week: Limit?
    var fable: Limit?
}

nonisolated enum UsageResult: Equatable { case ok(Usage), notFound, signedOut, failed }

/// Reads Claude Code's reply to a `get_usage` control request. Returns nil for any other stream line.
nonisolated func parseReply(_ line: String) -> UsageResult? {
    guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          json["type"] as? String == "control_response",
          let reply = json["response"] as? [String: Any] else { return nil }
    guard reply["subtype"] as? String == "success", let body = reply["response"] as? [String: Any] else { return .failed }
    if body["rate_limits_available"] as? Bool == false { return .signedOut }
    guard let limits = body["rate_limits"] as? [String: Any], let usage = parseUsage(limits) else { return .failed }
    return .ok(usage)
}

/// Reads the documented `rate_limits` fields. A missing window stays nil (shown as "-").
/// Not the raw `limits[]` array: Claude Code drops it when it answers from its own recent snapshot,
/// so it only supplies the optional severity.
nonisolated func parseUsage(_ json: [String: Any]) -> Usage? {
    let list = json["limits"] as? [[String: Any]]
    func limit(_ window: Any?, _ kind: String, _ isMine: ([String: Any]) -> Bool = { _ in true }) -> Limit? {
        guard let window = window as? [String: Any], let used = window["utilization"] as? NSNumber else { return nil }
        let severity = list.map { $0.first { $0["kind"] as? String == kind && isMine($0) }?["severity"] as? String ?? "normal" }
        return Limit(percent: Int(used.doubleValue), resetsAt: parseDate(window["resets_at"]),
                     locked: !((window["locked_reason"] ?? NSNull()) is NSNull), severity: severity)
    }
    func fable(_ name: Any?) -> Bool { (name as? String)?.lowercased().contains("fable") == true }
    let scoped = json["model_scoped"] as? [[String: Any]] ?? []
    let usage = Usage(session: limit(json["five_hour"], "session"), week: limit(json["seven_day"], "weekly_all"),
                      fable: limit(scoped.first { fable($0["display_name"]) }, "weekly_scoped") {
                          fable((($0["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"])
                      })
    return usage.session == nil && usage.week == nil ? nil : usage
}

/// resets_at can drift by fractions of a second between replies; real windows are hours apart.
nonisolated func sameWindow(_ a: Limit?, _ b: Limit?) -> Bool {
    guard let x = a?.resetsAt, let y = b?.resetsAt else { return false }
    return abs(x.timeIntervalSince(y)) < 3600
}

/// Reuses the last known severity of the same window, so the warning doesn't blink on snapshot answers.
nonisolated func keepSeverity(_ new: Usage, from old: Usage?) -> Usage {
    func keep(_ limit: Limit?, _ before: Limit?) -> Limit? {
        guard var limit, limit.severity == nil, sameWindow(limit, before) else { return limit }
        limit.severity = before?.severity
        return limit
    }
    return Usage(session: keep(new.session, old?.session), week: keep(new.week, old?.week), fable: keep(new.fable, old?.fable))
}

/// The first limit Claude flags: locked out, or any severity other than normal.
nonisolated func warning(_ usage: Usage?) -> String? {
    for (id, limit) in [("session", usage?.session), ("week", usage?.week), ("fable", usage?.fable)] {
        guard let limit else { continue }
        if limit.locked { return tr("reached.\(id)") }
        if let severity = limit.severity, severity != "normal" {
            // Claude's own word for it, which only comes in English.
            return tr("flagged_as", ["limit": tr("limit.\(id)"), "severity": severity.replacingOccurrences(of: "_", with: " ")])
        }
    }
    return nil
}

/// One successful refresh. The app keeps a day of these to measure how fast S and W rise.
nonisolated struct Sample: Codable, Equatable {
    var at: Date
    var usage: Usage
}

/// How fast a limit rose since the last reading at least `window` old, in percent per `unit`.
/// A limit window lasts `length`. Nil without such a reading in the same limit window.
nonisolated func speed(_ samples: [Sample], _ limit: KeyPath<Usage, Limit?>,
                       length: TimeInterval, window: TimeInterval, unit: TimeInterval) -> Double? {
    guard let latest = samples.last, let now = latest.usage[keyPath: limit], let reset = now.resetsAt else { return nil }
    let start = latest.at.addingTimeInterval(-window)
    var base = 0, elapsed = window  // the limit started over inside the window, from 0
    if reset.addingTimeInterval(-length) < start {
        guard let before = samples.last(where: { $0.at <= start && sameWindow($0.usage[keyPath: limit], now) }) else { return nil }
        base = before.usage[keyPath: limit]?.percent ?? 0
        // After a pause that reading can be hours old: spread the rise over all of it.
        elapsed = latest.at.timeIntervalSince(before.at)
    }
    return Double(max(0, now.percent - base)) * unit / elapsed
}

nonisolated enum Pace: Comparable {
    case ok, fast, tooFast
    var color: NSColor? { self == .ok ? nil : self == .fast ? .systemOrange : .systemRed }
}

/// How fast a limit rises against the pace it can keep until the reset, both in percent per `unit`.
nonisolated struct Rate {
    var speed: Double?
    var needed: Double?
    var unit: TimeInterval
    var margin: Double

    /// Orange once faster than needed, red once `margin` points past it.
    var pace: Pace {
        guard let speed, let needed else { return .ok }
        return speed > needed + margin ? .tooFast : speed > needed ? .fast : .ok
    }

    /// Why it's colored: "Using 24% a day, 17% a day lasts until reset".
    var reason: String? {
        guard pace != .ok else { return nil }
        let rate = unit == 3600 ? "rate_hour" : "rate_day"
        return tr("reason", ["speed": tr(rate, ["n": percent(speed)]), "needed": tr(rate, ["n": percent(needed)])])
    }
}

/// What's left spread evenly until the reset, in percent per `unit`.
nonisolated func evenPace(_ limit: Limit?, unit: TimeInterval, now: Date) -> Double? {
    guard let limit, let reset = limit.resetsAt, reset > now else { return nil }
    return Double(max(0, 100 - limit.percent)) * unit / reset.timeIntervalSince(now)
}

/// S per hour over the last 30 minutes against what's left spread evenly.
/// W over the last hour against the budget, per day, or per hour when `colors` is "hour": these are P and B.
/// Only `workHours` of each day are spent using Claude: P per day is the hourly rise times that,
/// and the budget per hour splits what's left over the working hours until the reset.
nonisolated func paces(_ usage: Usage?, samples: [Sample], colors: String, workHours: Double = 24,
                       now: Date) -> (session: Rate, week: Rate) {
    let hour: TimeInterval = 3600, unit = colors == "hour" ? hour : 24 * hour
    let session = speed(samples, \.session, length: 5 * hour, window: hour / 2, unit: hour)
    let week = speed(samples, \.week, length: 7 * 24 * hour, window: hour, unit: colors == "hour" ? hour : workHours * hour)
    let allowed = usage?.week.flatMap { budget(week: $0.percent, resetsAt: $0.resetsAt, unit: unit, workHours: workHours, now: now) }
    return (Rate(speed: session, needed: evenPace(usage?.session, unit: hour, now: now), unit: hour, margin: 5),
            Rate(speed: week, needed: allowed, unit: unit, margin: 10))
}

/// What a notification is about. Each kind has its own setting, all on by default.
nonisolated enum NoticeKind {
    case reached, reset, week

    var setting: String {
        switch self {
        case .reached: "notifyReached"
        case .reset: "notifyReset"
        case .week: "notifyWeek"
        }
    }
}

nonisolated struct Notice: Equatable {
    var kind: NoticeKind
    var id: String       // one per limit and kind, so a newer notice replaces an older one
    var title: String
    var body: String
    var at: Date? = nil  // delivered then instead of now
}

/// What happened between the previous reading and this one: a limit reached, which also schedules
/// the notice that it's usable again for its reset time, or the week crossing 80% or 90% in one window.
nonisolated func notices(from old: Usage?, to new: Usage, now: Date) -> [Notice] {
    var found: [Notice] = []
    for (id, before, after) in [("session", old?.session, new.session), ("week", old?.week, new.week),
                                ("fable", old?.fable, new.fable)] {
        guard let after, after.locked, before?.locked != true else { continue }
        found.append(Notice(kind: .reached, id: "reached-\(id)", title: tr("reached.\(id)"),
                            body: after.resetsAt.map { tr("notice_resets", ["time": span($0.timeIntervalSince(now))]) } ?? ""))
        if let reset = after.resetsAt, reset > now {
            found.append(Notice(kind: .reset, id: "reset-\(id)", title: tr("reset_done.\(id)"),
                                body: tr("use_again", ["name": id == "fable" ? "Fable" : "Claude"]), at: reset))
        }
    }
    // Only the highest mark crossed, and not when the week just ran out: that has its own notice.
    if let before = old?.week, let after = new.week, !after.locked, sameWindow(before, after),
       let mark = [90, 80].first(where: { before.percent < $0 && after.percent >= $0 }) {
        let left = max(0, 100 - after.percent)
        found.append(Notice(kind: .week, id: "week", title: tr("week_at", ["n": mark]),
                            body: after.resetsAt.map { tr("left_resets", ["n": left, "time": span($0.timeIntervalSince(now))]) }
                                ?? tr("left", ["n": left])))
    }
    return found
}

/// ISO 8601 string (any fractional digits) or epoch seconds.
nonisolated func parseDate(_ value: Any?) -> Date? {
    if let seconds = value as? NSNumber { return Date(timeIntervalSince1970: seconds.doubleValue) }
    guard let text = value as? String else { return nil }
    // Older Foundation rejects 6-digit fractions, and sub-second precision is irrelevant here.
    return ISO8601DateFormatter().date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
}

/// B: what's left of the weekly limit split over the whole days (or hours) until the reset, a partial
/// last one counting in full, rounded down to whole percents a day or tenths an hour.
/// 35% left over 1d 17h is 17% a day, or 0.8% an hour. Per hour only `workHours` of each day count.
nonisolated func budget(week: Int, resetsAt: Date?, unit: TimeInterval, workHours: Double = 24, now: Date) -> Double? {
    let remaining = max(0, 100 - week)
    if remaining == 0 { return 0 }
    guard let resetsAt else { return nil }
    let left = resetsAt.timeIntervalSince(now) * (unit < 86400 ? workHours / 24 : 1)
    // The epsilon keeps float noise (3.000000001) from rounding up to the next day.
    let units = (left / unit - 1e-9).rounded(.up)
    guard units > 0 else { return Double(remaining) }
    let steps: Double = unit < 86400 ? 10 : 1
    return (Double(remaining) * steps / units).rounded(.down) / steps
}

nonisolated func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "-" }
nonisolated func percent(_ value: Double?) -> String {
    value.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "-"
}

/// P and B are W's speed and budget. With `resetsFrom`, S, W and F add the time to their reset: "S 54% (1h13)".
/// A `profile` name goes first.
nonisolated func barText(_ usage: Usage?, rates: (session: Rate, week: Rate)? = nil, showFable: Bool, showPace: Bool = false,
                         showBudget: Bool, resetsFrom now: Date? = nil, profile: String? = nil) -> NSAttributedString {
    func stat(_ letter: String, _ limit: Limit?) -> String {
        guard let now, let reset = limit?.resetsAt else { return "\(letter) \(percent(limit?.percent))" }
        return "\(letter) \(percent(limit?.percent)) (\(span(reset.timeIntervalSince(now), short: true)))"
    }
    var parts = [(stat("S", usage?.session), rates?.session.pace ?? .ok),
                 (stat("W", usage?.week), rates?.week.pace ?? .ok)]
    if showFable { parts.append((stat("F", usage?.fable), .ok)) }
    if showPace { parts.append(("P \(percent(rates?.week.speed))", .ok)) }
    if showBudget { parts.append(("B \(percent(rates?.week.needed))", .ok)) }
    if let profile { parts.insert((profile, .ok), at: 0) }
    return joined(parts.map { text, pace in NSAttributedString(string: text, attributes: pace.color.map { [.foregroundColor: $0] } ?? [:]) })
}

/// The parts with " · " between them, in the menu bar's font.
nonisolated func joined(_ parts: [NSAttributedString]) -> NSAttributedString {
    let line = NSMutableAttributedString()
    for part in parts {
        if line.length > 0 { line.append(NSAttributedString(string: " · ")) }
        line.append(part)
    }
    line.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular), range: NSRange(location: 0, length: line.length))
    return line
}

/// The app icon's tilted five-ray star, one color. A template in the menu bar's own color unless tinted.
nonisolated func star(_ tint: NSColor?) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        // Same construction as Icon/make-icon.swift: each ray is the hull of a hub circle and a tip circle.
        let hub: CGFloat = 66, tip: CGFloat = 14, length: CGFloat = 245, tilt = -14 * CGFloat.pi / 180
        let spread = asin((hub - tip) / length)
        func point(_ centre: NSPoint, _ radius: CGFloat, _ angle: CGFloat) -> NSPoint {
            NSPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
        }
        let path = NSBezierPath()
        for ray in 0..<5 {
            let angle = CGFloat.pi / 2 + tilt + CGFloat(ray) * 2 * .pi / 5, end = point(.zero, length, angle)
            path.move(to: point(.zero, hub, angle - .pi / 2 - spread))
            path.line(to: point(end, tip, angle - .pi / 2 - spread))
            path.line(to: point(end, tip, angle + .pi / 2 + spread))
            path.line(to: point(.zero, hub, angle + .pi / 2 + spread))
            path.close()
            path.appendOval(in: NSRect(x: end.x - tip, y: end.y - tip, width: 2 * tip, height: 2 * tip))
        }
        path.appendOval(in: NSRect(x: -hub, y: -hub, width: 2 * hub, height: 2 * hub))
        let box = path.bounds
        path.transform(using: AffineTransform(translationByX: -box.midX, byY: -box.midY))
        path.transform(using: AffineTransform(scale: min(rect.width / box.width, rect.height / box.height)))
        path.transform(using: AffineTransform(translationByX: rect.midX, byY: rect.midY))
        (tint ?? .black).setFill()
        path.fill()
        return true
    }
    image.isTemplate = tint == nil
    image.accessibilityDescription = "ClaudioStat"
    return image
}

/// The image at `alpha` opacity, `lift` points higher over added transparent space.
/// A template stays one, so the menu bar still draws it in its own color.
nonisolated func redrawn(_ image: NSImage?, alpha: CGFloat = 1, lift: CGFloat = 0) -> NSImage? {
    guard let image else { return nil }
    let copy = NSImage(size: NSSize(width: image.size.width, height: image.size.height + 2 * lift), flipped: false) { _ in
        image.draw(in: NSRect(origin: NSPoint(x: 0, y: 2 * lift), size: image.size), from: .zero, operation: .sourceOver, fraction: alpha)
        return true
    }
    copy.isTemplate = image.isTemplate
    copy.accessibilityDescription = image.accessibilityDescription
    return copy
}

/// The text at `alpha` opacity, colored parts keeping their color.
nonisolated func faded(_ text: NSAttributedString, _ alpha: CGFloat) -> NSAttributedString {
    let copy = NSMutableAttributedString(attributedString: text)
    copy.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: copy.length)) { color, range, _ in
        copy.addAttribute(.foregroundColor, value: ((color as? NSColor) ?? .labelColor).withAlphaComponent(alpha), range: range)
    }
    return copy
}

/// "3d 18h", "2h 13m", "7m", or short for the menu bar: "3d18h", "2h13", "7m". Each language has its own units.
nonisolated func span(_ seconds: TimeInterval, short: Bool = false) -> String {
    let minutes = max(0, Int(seconds / 60)), days = minutes / 1440, hours = minutes / 60 % 24
    let form = days > 0 ? "dh" : hours > 0 ? "hm" : "m"
    return tr("span.\(form)\(short ? "_short" : "")",
              ["d": days, "h": hours, "m": minutes % 60, "mm": String(format: "%02d", minutes % 60)])
}
