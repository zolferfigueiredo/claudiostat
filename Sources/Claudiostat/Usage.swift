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
    for (name, limit) in [("Session", usage?.session), ("Week", usage?.week), ("Fable", usage?.fable)] {
        guard let limit else { continue }
        if limit.locked { return "\(name) limit reached" }
        if let severity = limit.severity, severity != "normal" {
            return "\(name) limit: \(severity.replacingOccurrences(of: "_", with: " "))"
        }
    }
    return nil
}

/// One successful refresh. The app keeps a day of these to measure how fast S and W rise.
nonisolated struct Sample: Codable, Equatable {
    var at: Date
    var usage: Usage
}

/// How much a limit rose over the last `window`, in percent per `unit`. A limit window lasts `length`.
/// Nil without a reading from before `window` in the same limit window.
nonisolated func speed(_ samples: [Sample], _ limit: KeyPath<Usage, Limit?>,
                       length: TimeInterval, window: TimeInterval, unit: TimeInterval) -> Double? {
    guard let latest = samples.last, let now = latest.usage[keyPath: limit], let reset = now.resetsAt else { return nil }
    let start = latest.at.addingTimeInterval(-window)
    var base = 0  // the limit started over inside the window, from 0
    if reset.addingTimeInterval(-length) < start {
        guard let before = samples.last(where: { $0.at <= start && sameWindow($0.usage[keyPath: limit], now) }) else { return nil }
        base = before.usage[keyPath: limit]?.percent ?? 0
    }
    return Double(max(0, now.percent - base)) * unit / window
}

nonisolated enum Pace: Comparable {
    case ok, fast, tooFast
    var color: NSColor? { self == .ok ? nil : self == .fast ? .systemOrange : .systemRed }
}

/// Orange once a limit rises faster than the pace that would use exactly what's left by the reset,
/// red once it's `margin` points (per `unit`) past that.
nonisolated func pace(speed: Double?, limit: Limit?, unit: TimeInterval, margin: Double, now: Date) -> Pace {
    guard let speed, let limit, let reset = limit.resetsAt, reset > now else { return .ok }
    let needed = Double(max(0, 100 - limit.percent)) * unit / reset.timeIntervalSince(now)
    return speed > needed + margin ? .tooFast : speed > needed ? .fast : .ok
}

/// S per hour over the last 30 minutes. W per day over the last 24 hours, or like S when `colors` is "hour".
nonisolated func paces(_ usage: Usage?, samples: [Sample], colors: String, now: Date) -> (session: Pace, week: Pace) {
    guard colors != "off" else { return (.ok, .ok) }
    let hour: TimeInterval = 3600, unit = colors == "hour" ? hour : 24 * hour
    let session = speed(samples, \.session, length: 5 * hour, window: hour / 2, unit: hour)
    let week = speed(samples, \.week, length: 7 * 24 * hour, window: unit == hour ? hour / 2 : unit, unit: unit)
    return (pace(speed: session, limit: usage?.session, unit: hour, margin: 5, now: now),
            pace(speed: week, limit: usage?.week, unit: unit, margin: 10, now: now))
}

/// ISO 8601 string (any fractional digits) or epoch seconds.
nonisolated func parseDate(_ value: Any?) -> Date? {
    if let seconds = value as? NSNumber { return Date(timeIntervalSince1970: seconds.doubleValue) }
    guard let text = value as? String else { return nil }
    // Older Foundation rejects 6-digit fractions, and sub-second precision is irrelevant here.
    return ISO8601DateFormatter().date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
}

/// L: what's left of the weekly limit, spread evenly per 24h until the weekly reset, rounded up.
nonisolated func dailyBudget(week: Int, resetsAt: Date?, now: Date) -> Int? {
    let remaining = max(0, 100 - week)
    if remaining == 0 { return 0 }
    guard let resetsAt else { return nil }
    let hours = resetsAt.timeIntervalSince(now) / 3600
    guard hours > 0 else { return remaining }
    // The epsilon keeps float noise (10.000000001) from rounding up to the next percent.
    return min(remaining, Int((Double(remaining) * 24 / hours - 1e-9).rounded(.up)))
}

nonisolated func budget(_ usage: Usage?, now: Date) -> Int? {
    guard let week = usage?.week else { return nil }
    return dailyBudget(week: week.percent, resetsAt: week.resetsAt, now: now)
}

nonisolated func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "-" }

nonisolated func barText(_ usage: Usage?, paces: (session: Pace, week: Pace) = (.ok, .ok),
                         showFable: Bool, showBudget: Bool, now: Date) -> NSAttributedString {
    var parts = [("S \(percent(usage?.session?.percent))", paces.session), ("W \(percent(usage?.week?.percent))", paces.week)]
    if showFable { parts.append(("F \(percent(usage?.fable?.percent))", .ok)) }
    if showBudget { parts.append(("L \(percent(budget(usage, now: now)))", .ok)) }
    let bar = NSMutableAttributedString()
    for (text, pace) in parts {
        if bar.length > 0 { bar.append(NSAttributedString(string: " · ")) }
        bar.append(NSAttributedString(string: text, attributes: pace.color.map { [.foregroundColor: $0] } ?? [:]))
    }
    bar.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
                     range: NSRange(location: 0, length: bar.length))
    return bar
}

/// "3d 18h", "2h 13m", "7m"
nonisolated func span(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60)), days = minutes / 1440, hours = minutes / 60 % 24
    return days > 0 ? "\(days)d \(hours)h" : hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
}
