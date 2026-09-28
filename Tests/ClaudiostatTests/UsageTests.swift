import Foundation
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
    #expect(barText(usage, showFable: true, showBudget: true, now: .now) == "S 42% · W - · F - · L -")
    #expect(barText(nil, showFable: false, showBudget: false, now: .now) == "S - · W -")
}

@Test func spans() {
    #expect(span(2 * 3600 + 13 * 60) == "2h 13m")
    #expect(span(3 * 86400 + 18 * 3600 + 59) == "3d 18h")
    #expect(span(7 * 60) == "7m")
    #expect(span(-5) == "0m")
}
