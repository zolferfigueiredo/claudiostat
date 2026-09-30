import AppKit
import Testing
@testable import ClaudioStat

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
/// Decimals follow the Mac's locale: "0.8" reads "0,8" in Portuguese.
private func local(_ text: String) -> String { text.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".") }

// What's left over whole days to the reset, a partial day counting as one, rounded down.
@Test(arguments: [
    ("2026-09-28T18:00:00Z", 56, "2026-10-01T18:00:00Z", 72.0, 14),  // Mon 18:00, 44 over 3 days
    ("2026-09-29T12:00:00Z", 70, "2026-10-01T18:00:00Z", 54.0, 10),  // Tue 12:00, 30 over 3 days
    ("2026-09-30T18:00:00Z", 90, "2026-10-01T18:00:00Z", 24.0, 10),  // Wed 18:00
    ("2026-10-01T18:00:00Z", 5, "2026-10-08T18:00:00Z", 168.0, 13),  // Thu 18:00 just reset, 95 over 7 days
    ("2026-10-01T12:00:00Z", 80, "2026-10-01T18:00:00Z", 6.0, 20),   // Thu 12:00, the last 6 hours are a day
    ("2026-09-29T18:00:00Z", 65, "2026-10-01T11:00:00Z", 41.0, 17),  // 35 over 1d 17h, 17.5 rounded down
])
func dailyBudgetTable(now: String, week: Int, reset: String, hours: Double, expected: Int) {
    #expect(date(reset).timeIntervalSince(date(now)) == hours * 3600)
    #expect(budget(week: week, resetsAt: date(reset), unit: 86400, now: date(now)) == Double(expected))
}

@Test func hourlyBudget() {
    // 35 over 41 hours is 0.85, rounded down to a tenth.
    #expect(budget(week: 65, resetsAt: date("2026-10-01T11:00:00Z"), unit: 3600, now: date("2026-09-29T18:00:00Z")) == 0.8)
}

@Test func weekUsedUpIsZero() {
    #expect(budget(week: 100, resetsAt: date("2026-10-01T18:00:00Z"), unit: 86400, now: date("2026-09-28T18:00:00Z")) == 0)
    #expect(budget(week: 100, resetsAt: nil, unit: 86400, now: .now) == 0)
    #expect(budget(week: 130, resetsAt: nil, unit: 86400, now: .now) == 0)
}

@Test func missingOrPassedReset() {
    #expect(budget(week: 50, resetsAt: nil, unit: 86400, now: .now) == nil)
    #expect(budget(week: 60, resetsAt: date("2026-10-01T18:00:00Z"), unit: 86400, now: date("2026-10-01T19:00:00Z")) == 40)
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
    #expect(barText(usage, showFable: true, showPace: true, showBudget: true).string == "S 42% · W - · F - · P - · D -")
    #expect(barText(nil, showFable: false, showBudget: false).string == "S - · W -")
    let rates = (Rate(unit: 3600, margin: 5), Rate(speed: 1, needed: 0.8, unit: 3600, margin: 10))
    #expect(barText(nil, rates: rates, showFable: false, showPace: true, showBudget: true).string == local("S - · W - · P 1% · D 0.8%"))
    let daily = (Rate(unit: 86400, margin: 5), Rate(speed: 16, needed: 13, unit: 86400, margin: 10))
    #expect(barText(nil, rates: daily, showFable: false, showBudget: true).string == "S - · W - · D 13%")
}

// Your examples: needed = what's left ÷ time left. Orange past it, red past it + 5 (S) or + 10 (W).
@Test(arguments: [
    (0, 5.0, 20.0, Pace.ok), (0, 5, 21, .fast), (0, 5, 25, .fast), (0, 5, 26, .tooFast),
    (50, 2, 25, .ok), (50, 2, 26, .fast), (50, 2, 30, .fast), (50, 2, 31, .tooFast),
    (50, 1, 50, .ok), (50, 1, 51, .fast), (50, 1, 55, .fast), (50, 1, 56, .tooFast),
])
func sessionPace(used: Int, hoursLeft: Double, speed: Double, expected: Pace) {
    let now = date("2026-09-28T12:00:00Z"), limit = Limit(percent: used, resetsAt: now.addingTimeInterval(hoursLeft * 3600))
    #expect(Rate(speed: speed, needed: evenPace(limit, unit: 3600, now: now), unit: 3600, margin: 5).pace == expected)
}

@Test func weekPace() {
    let now = date("2026-09-28T18:00:00Z"), week = Limit(percent: 56, resetsAt: date("2026-10-01T18:00:00Z"))  // 44% over 3 days
    let daily = budget(week: 56, resetsAt: week.resetsAt, unit: 86400, now: now)!  // 14 %/day
    func day(_ speed: Double?) -> Pace { Rate(speed: speed, needed: daily, unit: 86400, margin: 10).pace }
    func hour(_ speed: Double) -> Pace { Rate(speed: speed, needed: evenPace(week, unit: 3600, now: now), unit: 3600, margin: 10).pace }
    #expect(day(14) == .ok)
    #expect(day(15) == .fast)
    #expect(day(25) == .tooFast)
    #expect(hour(0.6) == .ok)       // needs 0.61 %/h
    #expect(hour(0.7) == .fast)
    #expect(hour(11) == .tooFast)
    #expect(day(nil) == .ok)
    #expect(evenPace(Limit(percent: 50, resetsAt: nil), unit: 3600, now: now) == nil)
}

private let reset = date("2026-09-28T15:00:00Z")  // session window 10:00 to 15:00
private func sample(_ time: String, s: Int, sReset: Date = reset, w: Int = 60) -> Sample {
    Sample(at: date(time), usage: Usage(session: Limit(percent: s, resetsAt: sReset),
                                        week: Limit(percent: w, resetsAt: date("2026-10-01T11:00:00Z"))))
}

@Test func speedOverLastHalfHour() {
    let samples = [sample("2026-09-28T11:20:00Z", s: 5), sample("2026-09-28T11:28:00Z", s: 10),
                   sample("2026-09-28T11:45:00Z", s: 18), sample("2026-09-28T12:00:00Z", s: 30)]
    // From the 11:28 reading (the last one before 11:30): 20 points in 32 minutes.
    #expect(speed(samples, \.session, length: 5 * 3600, window: 1800, unit: 3600) == 37.5)
}

@Test func speedAfterAPause() {
    // Paused from 04:00 to 12:00: the 4 points spread over all 8 hours, not the last one.
    let samples = [sample("2026-09-28T04:00:00Z", s: 0, w: 56), sample("2026-09-28T12:00:00Z", s: 0, w: 60)]
    #expect(speed(samples, \.week, length: 7 * 86400, window: 3600, unit: 86400) == 12)
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

@Test func weekPaceAgainstTheBudget() {
    // The last reading at least an hour old is 10:30, so the 1 point spreads over 1.5 hours.
    let samples = [sample("2026-09-28T10:30:00Z", s: 0, w: 59), sample("2026-09-28T12:00:00Z", s: 0, w: 60)]
    let usage = samples.last!.usage, now = date("2026-09-28T12:00:00Z")  // 40% left over 71h
    let day = paces(usage, samples: samples, colors: "day", now: now).week
    #expect(day.speed == 16 && day.needed == 13 && day.pace == .fast)  // 40 over 3 days
    #expect(day.reason == "Using 16% a day, 13% a day lasts until reset")
    let hour = paces(usage, samples: samples, colors: "hour", now: now).week
    #expect(hour.needed == 0.5 && hour.pace == .fast)  // 40 over 71 hours, 0.56 rounded down
    #expect(hour.reason == local("Using 0.7% an hour, 0.5% an hour lasts until reset"))
    let off = paces(usage, samples: samples, colors: "off", now: now).week
    #expect(off.speed == 16 && off.needed == 13 && off.pace == .ok && off.reason == nil)  // P and L still show
}

@Test func workingTimeScalesTheWeek() {
    // Same readings as above: 1 point over 1.5 hours, 40% left over 71h.
    let samples = [sample("2026-09-28T10:30:00Z", s: 0, w: 59), sample("2026-09-28T12:00:00Z", s: 0, w: 60)]
    let usage = samples.last!.usage, now = date("2026-09-28T12:00:00Z")
    let day = paces(usage, samples: samples, colors: "day", workHours: 8, now: now)
    #expect(abs(day.week.speed! - 16.0 / 3) < 1e-9 && day.week.needed == 13 && day.week.pace == .ok)  // days stay days
    let hour = paces(usage, samples: samples, colors: "hour", workHours: 8, now: now).week
    #expect(hour.needed == 1.6 && hour.pace == .ok)  // 40 over the 24 working hours in 71h (23.7 rounded up)
    #expect(day.session.needed == paces(usage, samples: samples, colors: "day", now: now).session.needed)  // S ignores it
}

@Test func paceIsTheLastHour() {
    let samples = [sample("2026-09-28T10:30:00Z", s: 0, w: 58), sample("2026-09-28T11:00:00Z", s: 0, w: 60),
                   sample("2026-09-28T11:30:00Z", s: 0, w: 61), sample("2026-09-28T12:00:00Z", s: 0, w: 62)]
    let usage = samples.last!.usage, now = date("2026-09-28T12:00:00Z")
    #expect(paces(usage, samples: samples, colors: "hour", now: now).week.speed == 2)  // 60 to 62 since 11:00
    #expect(paces(usage, samples: samples, colors: "day", now: now).week.speed == 48)
    #expect(paces(usage, samples: Array(samples.suffix(2)), colors: "day", now: now).week.speed == nil)
}

@Test func barColorsSessionAndWeekOnly() {
    let rates = (Rate(speed: 22, needed: 20, unit: 3600, margin: 5), Rate(speed: 30, needed: 13, unit: 86400, margin: 10))
    let bar = barText(Usage(session: Limit(percent: 30), week: Limit(percent: 60)), rates: rates, showFable: true, showBudget: false)
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

@Test func noticesWhenALimitIsReached() {
    let now = date("2026-09-28T12:00:00Z"), reset = date("2026-09-28T14:13:00Z")
    let before = Usage(session: Limit(percent: 97, resetsAt: reset), week: Limit(percent: 50))
    let after = Usage(session: Limit(percent: 100, resetsAt: reset, locked: true), week: Limit(percent: 50))
    let found = notices(from: before, to: after, now: now)
    #expect(found.map(\.id) == ["reached-session", "reset-session"])
    #expect(found[0].title == "Session limit reached" && found[0].body == "Resets in 2h 13m.")
    #expect(found[1].title == "Session limit reset" && found[1].at == reset && found[1].body == "You can use Claude again.")
    #expect(notices(from: after, to: after, now: now).isEmpty)  // no repeats while it stays reached
}

@Test func noticesWhenTheWeekCrossesAMark() {
    let now = date("2026-09-28T12:00:00Z"), reset = date("2026-10-01T16:00:00Z")  // 3d 4h away
    func week(_ percent: Int) -> Usage { Usage(week: Limit(percent: percent, resetsAt: reset)) }
    #expect(notices(from: week(79), to: week(80), now: now).map(\.title) == ["Week at 80%"])
    #expect(notices(from: week(79), to: week(80), now: now).first?.body == "20% left, resets in 3d 4h.")
    #expect(notices(from: week(79), to: week(93), now: now).map(\.title) == ["Week at 90%"])  // the highest mark only
    #expect(notices(from: week(80), to: week(85), now: now).isEmpty)
    // A new window (another reset time) starting high is not a crossing.
    let next = Usage(week: Limit(percent: 85, resetsAt: reset.addingTimeInterval(7 * 86400)))
    #expect(notices(from: week(10), to: next, now: now).isEmpty)
    // Running out is its own notice, not also a mark.
    let out = Usage(week: Limit(percent: 100, resetsAt: reset, locked: true))
    #expect(notices(from: week(85), to: out, now: now).map(\.kind) == [.reached, .reset])
}
