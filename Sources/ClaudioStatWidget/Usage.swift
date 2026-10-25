// Copied from appclaudiostat's apps/mobile/targets/_shared for the desktop widget: copy it again when it changes there. Changed here: the group's name.
import Foundation

// Shared by the iPhone widget, the watch app and its complications (apple-targets links targets/_shared into every
// target). Mirrors src/format.ts and src/pace.ts; packages/shared/fixtures checks both (scripts/swift-test.sh).
// Foundation only, so the Mac can compile and test it.

/// The app (or, on the watch, the watch app) writes "token", "api", "settings" and the last "reply" here.
// The Mac app (Sources/ClaudioStat/Widget.swift) writes them, not the phone app.
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

/// Written by the app (src/settings.ts); a field it doesn't write yet keeps ClaudioStat's default.
struct Settings: Codable {
    var colors = "day"
    var workHours = 8.0
    /// "rings" or "bars", and the limit whose number is large: "s", "w" or "f". Session and week always show.
    var style = "rings"
    var main = "s"
    var showPace = true
    var showBudget = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = try c.decodeIfPresent(String.self, forKey: .colors) ?? colors
        workHours = try c.decodeIfPresent(Double.self, forKey: .workHours) ?? workHours
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? style
        main = try c.decodeIfPresent(String.self, forKey: .main) ?? main
        showPace = try c.decodeIfPresent(Bool.self, forKey: .showPace) ?? showPace
        showBudget = try c.decodeIfPresent(Bool.self, forKey: .showBudget) ?? showBudget
    }

    static var current: Settings {
        appGroup?.string(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: Data($0.utf8)) }
            ?? Settings()
    }
}

enum Pace {
    case ok, fast, tooFast
}

/// ClaudioStat's span(): "3d 18h", "2h 13m", "7m".
func span(_ seconds: Int) -> String {
    let minutes = max(0, seconds / 60)
    let d = minutes / 1440, h = minutes / 60 % 24, m = minutes % 60
    return d > 0 ? String(localized: "\(d)d \(h)h") : h > 0 ? String(localized: "\(h)h \(m)m") : String(localized: "\(m)m")
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
    settings.colors == "hour" ? String(localized: "/h") : String(localized: "/day")
}

/// "Under budget" or "Over budget", once P and B are both known and shown.
func verdict(_ r: Rates, _ settings: Settings) -> String? {
    guard settings.showPace, settings.showBudget, r.p != nil, r.b != nil else { return nil }
    return r.w == .ok ? String(localized: "Under budget") : String(localized: "Over budget")
}

/// "Pace 15.6%/day, Budget 13%/day, Over budget", for VoiceOver.
func spokenRates(_ r: Rates, _ settings: Settings) -> String {
    let unit = rateUnit(settings)
    var parts: [String] = []
    if settings.showPace { parts.append(String(localized: "Pace \(rateText(r.p))\(unit)")) }
    if settings.showBudget { parts.append(String(localized: "Budget \(rateText(r.b))\(unit)")) }
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

/// ClaudioStat's warning(): locked out first, then a severity other than normal. Not from the status line.
func warning(_ snap: Snap) -> String? {
    guard snap.src != "sl" else { return nil }
    let limits: [(String, String, Limit?)] = [
        (String(localized: "Session limit"), String(localized: "Session limit reached"), snap.s),
        (String(localized: "Week limit"), String(localized: "Week limit reached"), snap.w),
        (String(localized: "Fable limit"), String(localized: "Fable limit reached"), snap.f),
    ]
    for (name, reached, limit) in limits {
        guard let limit else { continue }
        if limit.locked == true { return reached }
        if let severity = limit.severity, severity != "normal" {
            return "\(name): \(severity.replacingOccurrences(of: "_", with: " "))"
        }
    }
    return nil
}

/// One Claude account on the phone (src/session.ts writes the list): its token and its email, the label.
struct StoredAccount: Codable, Hashable {
    let id: String
    let token: String
    let email: String?

    /// "me" for me@example.com, else "Account 2".
    func label(_ index: Int) -> String {
        email.flatMap { $0.split(separator: "@").first.map(String.init) } ?? String(localized: "Account \(index + 1)")
    }
}

/// The phone's accounts; a phone (or watch) from before several accounts has its one token alone.
func storedAccounts() -> [StoredAccount] {
    if let json = appGroup?.string(forKey: "accounts"),
       let accounts = try? JSONDecoder().decode([StoredAccount].self, from: Data(json.utf8)) {
        return accounts
    }
    return appGroup?.string(forKey: "token").map { [StoredAccount(id: "first", token: $0, email: nil)] } ?? []
}

/// The account the app shows, which the widgets show unless they're set to another.
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

/// GET /v1/snapshot with the account's token; keeps a copy for when the API can't be reached.
func fetchReply(_ account: StoredAccount? = currentAccount(), _ done: @escaping (Reply?) -> Void) {
    guard let account, let api = appGroup?.string(forKey: "api"),
          let url = URL(string: api + "/v1/snapshot") else { return done(nil) }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: request) { data, response, _ in
        // Logged out of this account on the phone: forget it, so the watch says to log in there.
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            forget(account)
            return done(nil)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return done(nil) }
        appGroup?.set(String(decoding: data, as: UTF8.self), forKey: "reply.\(account.id)")
        if account.id == currentAccount()?.id { appGroup?.set(String(decoding: data, as: UTF8.self), forKey: "reply") }
        done(reply)
    }.resume()
}

private func forget(_ account: StoredAccount) {
    let rest = storedAccounts().filter { $0.id != account.id }
    appGroup?.removeObject(forKey: "reply.\(account.id)")
    if let json = try? JSONEncoder().encode(rest) { appGroup?.set(String(decoding: json, as: UTF8.self), forKey: "accounts") }
    if let next = rest.first {
        if appGroup?.string(forKey: "current") == account.id || appGroup?.string(forKey: "current") == nil {
            appGroup?.set(next.id, forKey: "current")
            appGroup?.set(next.token, forKey: "token")
        }
    } else {
        appGroup?.removeObject(forKey: "token")
        appGroup?.removeObject(forKey: "reply")
        appGroup?.removeObject(forKey: "current")
        // The pairing is gone, so the watch's token too: the next login hands the watch a new one.
        appGroup?.removeObject(forKey: "watchToken")
    }
}
