import Foundation

nonisolated struct Limit: Equatable {
    var percent: Int
    var resetsAt: Date?
}

nonisolated struct Usage: Equatable {
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
/// Not the raw `limits[]` array: Claude Code drops it when it answers from its own recent snapshot.
nonisolated func parseUsage(_ json: [String: Any]) -> Usage? {
    func limit(_ window: Any?) -> Limit? {
        guard let window = window as? [String: Any], let used = window["utilization"] as? NSNumber else { return nil }
        return Limit(percent: Int(used.doubleValue), resetsAt: parseDate(window["resets_at"]))
    }
    let scoped = json["model_scoped"] as? [[String: Any]] ?? []
    let usage = Usage(session: limit(json["five_hour"]), week: limit(json["seven_day"]),
                      fable: limit(scoped.first { ($0["display_name"] as? String)?.lowercased().contains("fable") == true }))
    return usage.session == nil && usage.week == nil ? nil : usage
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

nonisolated func barText(_ usage: Usage?, showFable: Bool, showBudget: Bool, now: Date) -> String {
    var parts = ["S \(percent(usage?.session?.percent))", "W \(percent(usage?.week?.percent))"]
    if showFable { parts.append("F \(percent(usage?.fable?.percent))") }
    if showBudget { parts.append("L \(percent(budget(usage, now: now)))") }
    return parts.joined(separator: " · ")
}

/// "3d 18h", "2h 13m", "7m"
nonisolated func span(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60)), days = minutes / 1440, hours = minutes / 60 % 24
    return days > 0 ? "\(days)d \(hours)h" : hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
}
