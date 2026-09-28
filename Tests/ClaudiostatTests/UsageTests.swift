import AppKit
import Testing
@testable import Claudiostat

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

// The spec's table, reset = Thursday 18:00.
@Test(arguments: [
    ("2026-09-28T18:00:00Z", 56, "2026-10-01T18:00:00Z", 72.0, 15),  // Mon 18:00, 14.67 rounded up
    ("2026-09-29T12:00:00Z", 70, "2026-10-01T18:00:00Z", 54.0, 14),  // Tue 12:00, 13.33 rounded up
    ("2026-09-30T18:00:00Z", 90, "2026-10-01T18:00:00Z", 24.0, 10),  // Wed 18:00
    ("2026-10-01T18:00:00Z", 5, "2026-10-08T18:00:00Z", 168.0, 14),  // Thu 18:00 just reset, 13.57 rounded up
    ("2026-10-01T12:00:00Z", 80, "2026-10-01T18:00:00Z", 6.0, 20),   // Thu 12:00, capped at what's left
])
func dailyBudgetTable(now: String, week: Int, reset: String, hours: Double, expected: Int) {
    #expect(date(reset).timeIntervalSince(date(now)) == hours * 3600)
    #expect(dailyBudget(week: week, resetsAt: date(reset), now: date(now)) == expected)
}

@Test func weekUsedUpIsZero() {
    #expect(dailyBudget(week: 100, resetsAt: date("2026-10-01T18:00:00Z"), now: date("2026-09-28T18:00:00Z")) == 0)
    #expect(dailyBudget(week: 100, resetsAt: nil, now: .now) == 0)
    #expect(dailyBudget(week: 130, resetsAt: nil, now: .now) == 0)
}

@Test func missingOrPassedReset() {
    #expect(dailyBudget(week: 50, resetsAt: nil, now: .now) == nil)
    #expect(dailyBudget(week: 60, resetsAt: date("2026-10-01T18:00:00Z"), now: date("2026-10-01T19:00:00Z")) == 40)
}

// Trimmed from a real Claude Code reply to the get_usage control request.
@Test func parsesClaudeCodeReply() throws {
    let line = """
    {"type":"control_response","response":{"subtype":"success","request_id":"1","response":{"session":{"total_cost_usd":0},\
    "subscription_type":"max","rate_limits_available":true,"rate_limits":{\
    "five_hour":{"utilization":27.6,"resets_at":"2026-09-28T17:40:00.203540+00:00","locked_reason":null},\
    "seven_day":{"utilization":58,"resets_at":"2026-10-01T11:00:00+00:00"},"seven_day_sonnet":null,\
    "model_scoped":[{"display_name":"Fable","utilization":7,"resets_at":"2026-10-01T11:00:00+00:00"}]},"behaviors":null}}}
    """
    guard case .ok(let usage) = try #require(parseReply(line)) else { Issue.record("not ok"); return }
    #expect(usage.session == Limit(percent: 27, resetsAt: date("2026-09-28T17:40:00Z")))  // floored, like /usage
    #expect(usage.week == Limit(percent: 58, resetsAt: date("2026-10-01T11:00:00Z")))
    #expect(usage.fable == Limit(percent: 7, resetsAt: date("2026-10-01T11:00:00Z")))
}

@Test func parsesEpochResetTimes() {
    #expect(parseDate(1790852400) == date("2026-10-01T11:00:00Z"))
    #expect(parseDate(NSNull()) == nil)
}

@Test func otherRepliesAndLines() {
    #expect(parseReply(#"{"type":"system","subtype":"init"}"#) == nil)
    #expect(parseReply("not json") == nil)
    #expect(parseReply(#"{"type":"control_response","response":{"subtype":"error","error":"x"}}"#) == .failed)
    #expect(parseReply(#"{"type":"control_response","response":{"subtype":"success","response":{"rate_limits_available":false,"rate_limits":null}}}"#) == .signedOut)
    #expect(parseReply(#"{"type":"control_response","response":{"subtype":"success","response":{"rate_limits_available":true,"rate_limits":null}}}"#) == .failed)
}

@Test func missingRowsShowDash() {
    let usage = parseUsage(["five_hour": ["utilization": 42, "resets_at": NSNull()], "model_scoped": []])
    #expect(barText(usage, showFable: true, showBudget: true, now: .now).string == "S 42% · W - · F - · L -")
    #expect(barText(nil, showFable: false, showBudget: false, now: .now).string == "S - · W -")
}

// Your examples: needed = what's left ÷ time left. Orange past it, red past it + 5 (S) or + 10 (W).
@Test(arguments: [
    (0, 5.0, 20.0, Pace.ok), (0, 5, 21, .fast), (0, 5, 25, .fast), (0, 5, 26, .tooFast),
    (50, 2, 25, .ok), (50, 2, 26, .fast), (50, 2, 30, .fast), (50, 2, 31, .tooFast),
    (50, 1, 50, .ok), (50, 1, 51, .fast), (50, 1, 55, .fast), (50, 1, 56, .tooFast),
])
func sessionPace(used: Int, hoursLeft: Double, speed: Double, expected: Pace) {
    let now = date("2026-09-28T12:00:00Z"), limit = Limit(percent: used, resetsAt: now.addingTimeInterval(hoursLeft * 3600))
    #expect(pace(speed: speed, limit: limit, unit: 3600, margin: 5, now: now) == expected)
}

@Test func weekPace() {
    let now = date("2026-09-28T18:00:00Z"), week = Limit(percent: 56, resetsAt: date("2026-10-01T18:00:00Z"))  // 44% over 3 days
    #expect(pace(speed: 14, limit: week, unit: 86400, margin: 10, now: now) == .ok)       // needs 14.67 %/day
    #expect(pace(speed: 15, limit: week, unit: 86400, margin: 10, now: now) == .fast)
    #expect(pace(speed: 25, limit: week, unit: 86400, margin: 10, now: now) == .tooFast)
    #expect(pace(speed: 0.6, limit: week, unit: 3600, margin: 10, now: now) == .ok)       // needs 0.61 %/h
    #expect(pace(speed: 0.7, limit: week, unit: 3600, margin: 10, now: now) == .fast)
    #expect(pace(speed: 11, limit: week, unit: 3600, margin: 10, now: now) == .tooFast)
    #expect(pace(speed: nil, limit: week, unit: 86400, margin: 10, now: now) == .ok)
    #expect(pace(speed: 99, limit: Limit(percent: 50, resetsAt: nil), unit: 3600, margin: 5, now: now) == .ok)
}

private let reset = date("2026-09-28T15:00:00Z")  // session window 10:00 to 15:00
private func sample(_ time: String, s: Int, sReset: Date = reset, w: Int = 60) -> Sample {
    Sample(at: date(time), usage: Usage(session: Limit(percent: s, resetsAt: sReset),
                                        week: Limit(percent: w, resetsAt: date("2026-10-01T11:00:00Z"))))
}

@Test func speedOverLastHalfHour() {
    let samples = [sample("2026-09-28T11:20:00Z", s: 5), sample("2026-09-28T11:28:00Z", s: 10),
                   sample("2026-09-28T11:45:00Z", s: 18), sample("2026-09-28T12:00:00Z", s: 30)]
    // From the 11:28 reading (the last one before 11:30): 20 points in half an hour.
    #expect(speed(samples, \.session, length: 5 * 3600, window: 1800, unit: 3600) == 40)
}

@Test func speedNeedsAnOlderReading() {
    #expect(speed([sample("2026-09-28T11:45:00Z", s: 18), sample("2026-09-28T12:00:00Z", s: 30)],
                  \.session, length: 5 * 3600, window: 1800, unit: 3600) == nil)
    #expect(speed([], \.session, length: 5 * 3600, window: 1800, unit: 3600) == nil)
}

@Test func speedIgnoresThePreviousWindow() {
    let samples = [sample("2026-09-28T11:00:00Z", s: 90, sReset: date("2026-09-28T10:00:00Z")),
                   sample("2026-09-28T12:00:00Z", s: 30)]
    #expect(speed(samples, \.session, length: 5 * 3600, window: 1800, unit: 3600) == nil)
}

@Test func speedFromZeroWhenTheWindowJustStarted() {
    // Session began 10 minutes ago, so its whole 12% counts against the half hour.
    let samples = [sample("2026-09-28T09:00:00Z", s: 80, sReset: date("2026-09-28T09:30:00Z")),
                   sample("2026-09-28T10:10:00Z", s: 12)]
    #expect(speed(samples, \.session, length: 5 * 3600, window: 1800, unit: 3600) == 24)
}

@Test func weekSpeedPerDay() {
    let samples = [sample("2026-09-27T11:00:00Z", s: 0, w: 40), sample("2026-09-27T13:00:00Z", s: 0, w: 45),
                   sample("2026-09-28T12:00:00Z", s: 0, w: 60)]
    #expect(speed(samples, \.week, length: 7 * 86400, window: 86400, unit: 86400) == 20)
    let usage = samples.last!.usage, now = date("2026-09-28T12:00:00Z")  // 40% left over 71h: needs 13.5 %/day
    #expect(paces(usage, samples: samples, colors: "day", now: now).week == .fast)
    #expect(paces(usage, samples: samples, colors: "off", now: now).week == .ok)
}

@Test func barColorsSessionAndWeekOnly() {
    let bar = barText(Usage(session: Limit(percent: 30), week: Limit(percent: 60)), paces: (.fast, .tooFast),
                      showFable: true, showBudget: false, now: .now)
    func color(_ text: String) -> NSColor? {
        bar.attribute(.foregroundColor, at: (bar.string as NSString).range(of: text).location, effectiveRange: nil) as? NSColor
    }
    #expect(bar.string == "S 30% · W 60% · F -")
    #expect(color("S 30%") == .systemOrange)
    #expect(color("W 60%") == .systemRed)
    #expect(color("F -") == nil)
}

// Trimmed from a real reply: locked_reason on each window, severity in the limits list.
@Test func parsesWarnings() {
    let usage = parseUsage([
        "five_hour": ["utilization": 97, "resets_at": "2026-09-28T23:00:00.881496+00:00", "locked_reason": NSNull()],
        "seven_day": ["utilization": 100, "resets_at": "2026-10-01T11:00:00+00:00", "locked_reason": "weekly_limit"],
        "model_scoped": [["display_name": "Fable", "utilization": 0, "resets_at": "2026-10-01T11:00:00+00:00"]],
        "limits": [["kind": "session", "severity": "warning"], ["kind": "weekly_all", "severity": "normal"],
                   ["kind": "weekly_scoped", "severity": "normal", "scope": ["model": ["display_name": "Fable"]]]],
    ])
    #expect(usage?.session?.severity == "warning")
    #expect(usage?.session?.locked == false)
    #expect(usage?.week?.locked == true)
    #expect(usage?.fable?.severity == "normal")
    #expect(warning(usage) == "Session limit: warning")
    #expect(warning(Usage(session: Limit(percent: 10, severity: "normal"))) == nil)
    #expect(warning(Usage(week: Limit(percent: 100, locked: true))) == "Week limit reached")
}

@Test func keepsSeverityWithinTheSameWindow() {
    let old = Usage(session: Limit(percent: 90, resetsAt: reset, severity: "warning"))
    #expect(keepSeverity(Usage(session: Limit(percent: 92, resetsAt: reset)), from: old).session?.severity == "warning")
    #expect(keepSeverity(Usage(session: Limit(percent: 92, resetsAt: reset, severity: "normal")), from: old).session?.severity == "normal")
    let after = Usage(session: Limit(percent: 2, resetsAt: reset.addingTimeInterval(5 * 3600)))
    #expect(keepSeverity(after, from: old).session?.severity == nil)
}

@Test func spans() {
    #expect(span(2 * 3600 + 13 * 60) == "2h 13m")
    #expect(span(3 * 86400 + 18 * 3600 + 59) == "3d 18h")
    #expect(span(7 * 60) == "7m")
    #expect(span(-5) == "0m")
}
