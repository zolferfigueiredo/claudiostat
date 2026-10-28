import ClaudioStatStrings
import Foundation

// The numbers the app leaves the widget (Sources/ClaudioStat/Widget.swift), and the pace and budget math on them.

/// The app writes "accounts", "current", "settings" and each profile's "reply" here.
let appGroup = UserDefaults(suiteName: "497V6MCDS8.com.zolfer.claudiostat")
let staleAfter = 3600

struct Limit: Codable {
    let pct: Int
    let reset: Int?
    let locked: Bool?
    let severity: String?
}

struct Snap: Codable {
    let src: String
    let s: Limit?
    let w: Limit?
    let f: Limit?
}

struct Speeds: Codable {
    let s: Double?
    let w: Double?
}

struct Reply: Codable {
    let snap: Snap
    let checkedAt: Int
    let speed: Speeds?
    /// The Claude login stopped working: these are the last numbers read.
    let loginNeeded: Bool?
}

/// Written by the app; a field it doesn't write keeps the default.
struct Settings: Codable {
    var colors = "day"
    var workHours = 8.0
    var showPace = true
    var showBudget = true
    /// The one picked in the app's menu: the widget speaks it too.
    var language: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = try c.decodeIfPresent(String.self, forKey: .colors) ?? colors
        workHours = try c.decodeIfPresent(Double.self, forKey: .workHours) ?? workHours
        showPace = try c.decodeIfPresent(Bool.self, forKey: .showPace) ?? showPace
        showBudget = try c.decodeIfPresent(Bool.self, forKey: .showBudget) ?? showBudget
        language = try c.decodeIfPresent(String.self, forKey: .language)
    }

    /// tr() reads the language from this process's defaults, and the widget's are its own: it takes the app's.
    func speak() {
        UserDefaults.standard.set(language, forKey: "language")
    }

    static var current: Settings {
        appGroup?.string(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: Data($0.utf8)) }
            ?? Settings()
    }
}

enum Pace {
    case ok, fast, tooFast
}

/// The app's span() for whole seconds: "3d 18h", "2h 13m", "7m".
func span(_ seconds: Int) -> String {
    ClaudioStatStrings.span(TimeInterval(seconds))
}

/// A limit whose reset passed is unknown until new numbers arrive.
func percentText(_ limit: Limit?, now: Int) -> String {
    "\(usedNow(limit, now: now))%"
}

/// What's used now: 0 once the limit's window has reset (or before any numbers), never a dash.
func usedNow(_ limit: Limit?, now: Int) -> Int {
    guard let limit, limit.reset.map({ $0 > now }) ?? true else { return 0 }
    return limit.pct
}

/// P and B's unit: "/day" or "/h".
func rateUnit(_ settings: Settings) -> String {
    tr(settings.colors == "hour" ? "per_hour" : "per_day")
}

/// "Under budget" or "Over budget", once P and B are both known and shown.
func verdict(_ r: Rates, _ settings: Settings) -> String? {
    guard settings.showPace, settings.showBudget, r.p != nil, r.b != nil else { return nil }
    return tr(r.w == .ok ? "under_budget" : "over_budget")
}

/// "Pace 15.6%/day, Budget 13%/day, Over budget", for VoiceOver.
func spokenRates(_ r: Rates, _ settings: Settings) -> String {
    let unit = rateUnit(settings)
    var parts: [String] = []
    if settings.showPace { parts.append("\(tr("pace")) \(rateText(r.p))\(unit)") }
    if settings.showBudget { parts.append("\(tr("budget")) \(rateText(r.b))\(unit)") }
    return (parts + [verdict(r, settings)].compactMap { $0 }).joined(separator: ", ")
}

/// P and B on one ring or bar: B marks the middle until P passes twice B; then the full ring is P and B slides back.
func paceScale(_ p: Double?, _ b: Double?) -> (fraction: Double, mark: Double?) {
    let wide = b.map { max(2 * $0, p ?? 0) } ?? max(p ?? 0, 1)
    let full = wide > 0 ? wide : 1
    return (p.map { min(1, $0 / full) } ?? 0, b.map { min(1, $0 / full) })
}

/// 0 to 1 decimals, like ClaudioStat's percent().
func rateText(_ value: Double?) -> String {
    "\((value ?? 0).formatted(.number.precision(.fractionLength(0...1))))%"
}

/// What's left spread evenly until the reset, in percent per `unit`.
func evenPace(_ limit: Limit?, unit: Double, now: Int) -> Double? {
    guard let limit, let reset = limit.reset, reset > now else { return nil }
    return Double(max(0, 100 - limit.pct)) * unit / Double(reset - now)
}

/// B: what's left of the week over the whole days (or working hours) until the reset, rounded down.
func budget(week: Int, reset: Int?, unit: Double, workHours: Double, now: Int) -> Double? {
    let remaining = max(0, 100 - week)
    if remaining == 0 { return 0 }
    guard let reset else { return nil }
    let left = Double(reset - now) * (unit < 86400 ? workHours / 24 : 1)
    // The epsilon keeps float noise (3.000000001) from rounding up to the next day.
    let units = (left / unit - 1e-9).rounded(.up)
    guard units > 0 else { return Double(remaining) }
    let steps: Double = unit < 86400 ? 10 : 1
    return (Double(remaining) * steps / units).rounded(.down) / steps
}

/// Orange once faster than needed, red once `margin` points past it.
func pace(_ speed: Double?, _ needed: Double?, margin: Double) -> Pace {
    guard let speed, let needed else { return .ok }
    return speed > needed + margin ? .tooFast : speed > needed ? .fast : .ok
}

/// P against B: orange past the budget, red from twice it, where the pace ring is full.
func overBudget(_ p: Double?, _ b: Double?) -> Pace {
    guard let p, let b else { return .ok }
    return p > 0 && p >= 2 * b ? .tooFast : p > b ? .fast : .ok
}

struct Rates {
    let s: Pace
    let w: Pace
    let p: Double?
    let b: Double?
}

/// S against an even spread per hour; W (P) against the budget (B), per day or per hour.
func rates(_ reply: Reply, _ settings: Settings, now: Int) -> Rates {
    let perHour = settings.colors == "hour"
    let p = reply.speed?.w.map { $0 * (perHour ? 1 : settings.workHours) }
    let b = reply.snap.w.flatMap {
        budget(week: $0.pct, reset: $0.reset, unit: perHour ? 3600 : 86400, workHours: settings.workHours, now: now)
    }
    return Rates(s: pace(reply.speed?.s, evenPace(reply.snap.s, unit: 3600, now: now), margin: 5),
                 w: overBudget(p, b), p: p, b: b)
}

/// The app's warning(): locked out first, then a severity other than normal while the limit is past its hand.
func warning(_ snap: Snap, now: Int) -> String? {
    for (id, limit, window) in [("session", snap.s, 5 * 3600), ("week", snap.w, 7 * 86400), ("fable", snap.f, 7 * 86400)] {
        guard let limit else { continue }
        if limit.locked == true { return tr("reached.\(id)") }
        if let severity = limit.severity, severity != "normal",
           Double(usedNow(limit, now: now)) > (elapsed(limit, window: window, now: now) ?? 0) * 100 {
            return tr("flagged_as", ["limit": tr("limit.\(id)"), "severity": severity.replacingOccurrences(of: "_", with: " ")])
        }
    }
    return nil
}

/// One of the app's profiles: its id and its name, the email it signed in with or its folder.
struct StoredAccount: Codable, Hashable {
    let id: String
    let email: String?

    /// "me" for me@example.com.
    var label: String {
        email.flatMap { $0.split(separator: "@").first.map(String.init) } ?? id
    }
}

func storedAccounts() -> [StoredAccount] {
    appGroup?.string(forKey: "accounts").flatMap { try? JSONDecoder().decode([StoredAccount].self, from: Data($0.utf8)) } ?? []
}

/// The profile checked in the app's menu.
func currentAccount() -> StoredAccount? {
    let accounts = storedAccounts()
    let current = appGroup?.string(forKey: "current")
    return accounts.first { $0.id == current } ?? accounts.first
}

func cachedReply(_ account: StoredAccount? = currentAccount()) -> Reply? {
    let key = account.map { "reply.\($0.id)" }
    let json = key.flatMap { appGroup?.string(forKey: $0) } ?? appGroup?.string(forKey: "reply")
    return json.flatMap { try? JSONDecoder().decode(Reply.self, from: Data($0.utf8)) }
}
