import ClaudioStatStrings
import Foundation
import WidgetKit

// The desktop widget (Sources/ClaudioStatWidget) can't run Claude Code, so the app leaves it each profile's numbers
// in their shared group.
let widgetGroup = UserDefaults(suiteName: "497V6MCDS8.com.zolfer.claudiostat")

/// A profile's numbers for the widget: resets in epoch seconds, S and W rising per hour.
nonisolated struct WidgetReply: Encodable {
    struct Used: Encodable {
        let pct: Int
        let reset: Int?
        let locked: Bool
        let severity: String?
    }

    struct Snap: Encodable {
        var src = "app"
        let s, w, f: Used?
    }

    struct Speeds: Encodable {
        let s, w: Double?
    }

    let snap: Snap
    let checkedAt: Int
    let speed: Speeds
    let loginNeeded: Bool?
}

nonisolated struct WidgetSettings: Encodable {
    let colors: String
    let workHours: Double
    let showPace: Bool
    let showBudget: Bool
    let language: String
}

/// Nil until the profile's first reading.
func widgetReply(_ account: Account) -> WidgetReply? {
    guard let usage = account.usage, let updated = account.updated else { return nil }
    func used(_ limit: Limit?) -> WidgetReply.Used? {
        limit.map { WidgetReply.Used(pct: $0.percent, reset: $0.resetsAt.map { Int($0.timeIntervalSince1970) }, locked: $0.locked,
                                     severity: $0.severity) }
    }
    // As pacing() measures them; the widget turns W's into P per day or per hour.
    let hour: TimeInterval = 3600
    return WidgetReply(snap: WidgetReply.Snap(s: used(usage.session), w: used(usage.week), f: used(usage.fable)),
                       checkedAt: Int(updated.timeIntervalSince1970),
                       speed: WidgetReply.Speeds(s: speed(account.samples, \.session, length: 5 * hour, window: hour / 2, unit: hour),
                                                 w: speed(account.samples, \.week, length: 7 * 24 * hour, window: hour, unit: hour)),
                       loginNeeded: account.problem == "signed_out" ? true : nil)
}

extension AppDelegate {
    /// After each refresh and each change of settings or profiles. Only what changed is written, then the widgets redraw.
    func shareWithWidget() {
        guard let group = widgetGroup else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // the same numbers make the same text, so nothing redraws for nothing
        func json(_ value: some Encodable) -> String? { (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } }
        // ~/.claude is "" here, and the widget's Edit Widget needs an id.
        func id(_ path: String) -> String { path.isEmpty ? "claude" : path }
        var values: [String: String?] = [
            "current": id(profile),
            "accounts": json(allProfiles.map { ["id": id($0), "token": "", "email": profileName($0)] }),
            "settings": json(WidgetSettings(colors: defaults.string(forKey: "speedColors") ?? "day",
                                            workHours: Double(defaults.integer(forKey: "workHours")),
                                            showPace: defaults.bool(forKey: "showPace"), showBudget: defaults.bool(forKey: "showBudget"),
                                            language: Language.current.rawValue)),
        ]
        // A profile without numbers keeps its last ones there.
        for path in allProfiles {
            guard let reply = accounts[path].flatMap(widgetReply).flatMap(json) else { continue }
            values["reply.\(id(path))"] = reply
            if path == profile { values["reply"] = reply }
        }
        let written = values.compactMapValues { $0 }
        guard written != sharedWithWidget else { return }
        for (key, value) in written { group.set(value, forKey: key) }
        sharedWithWidget = written
        WidgetCenter.shared.reloadAllTimelines()
    }
}
