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
