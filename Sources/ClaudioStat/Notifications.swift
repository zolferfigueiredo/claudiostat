import Foundation
import UserNotifications

/// Posts the notices whose setting is on, asking for permission the first time. Reset notices wait for
/// their reset time, so they arrive even while ClaudioStat is paused.
func post(_ notices: [Notice], settings: UserDefaults) {
    let wanted = notices.filter { settings.bool(forKey: $0.kind.setting) }
    guard !wanted.isEmpty else { return }
    Task {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        for notice in wanted {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            let trigger = notice.at.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
            try? await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
        }
    }
}

/// Launch argument `-testNotifications YES`: the update notice at once, then each warning 8 seconds apart,
/// to check how they read. The warnings come from notices(from:to:now:) on made-up readings, so they say
/// exactly what real ones would. The Notifications toggles still apply.
func testNotifications() {
    Task { _ = await showUpdateNotification(nextPatch(appVersion)) }
    let now = Date.now, reset = now.addingTimeInterval(3 * 86400 + 4 * 3600)
    let open = Limit(percent: 99, resetsAt: reset), reached = Limit(percent: 100, resetsAt: reset, locked: true)
    func week(_ percent: Int) -> Usage { Usage(week: Limit(percent: percent, resetsAt: reset)) }
    let changes = [(week(79), week(80)), (week(89), week(90)), (Usage(session: open), Usage(session: reached)),
                   (Usage(week: open), Usage(week: reached)), (Usage(fable: open), Usage(fable: reached))]
    // Not the "usable again" notices a reached limit also schedules: those aren't warnings.
    let warnings = changes.flatMap { notices(from: $0, to: $1, now: now) }.filter { $0.kind != .reset }
    post(warnings.enumerated().map { index, warning in
        var warning = warning
        warning.id = "test-\(index + 1)"  // else 90% would replace 80%, which has the same id
        warning.at = now.addingTimeInterval(8 * Double(index + 1))
        return warning
    }, settings: .standard)
}
