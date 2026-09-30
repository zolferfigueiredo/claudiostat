import AppKit
import UserNotifications
import os

let log = Logger(subsystem: "com.zolfer.claudiostat", category: "app")

/// One profile's readings.
struct Account {
    var usage: Usage?        // nil after a failed fetch: dashes, never stale numbers
    var samples: [Sample] = []
    var updated: Date?
    var failedAt: Date?
    var problem: String?     // Claude Code missing or signed out
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    // Launch argument `-watchBundleID com.apple.TextEdit` tests pause/resume without quitting Claude.
    lazy var claudeID = defaults.string(forKey: "watchBundleID") ?? "com.anthropic.claudefordesktop"

    var accounts: [String: Account] = [:]  // by profile
    var claudeRunning = false
    var busy = false
    var timer: Timer?
    var pulse: Timer?        // redraws the icon or numbers while they fade
    var midReply: [String: Date] = [:]  // Claude Code transcripts mid-reply, by when they were last written
    var sessions: FSEventStreamRef?  // watches the shown profiles' transcripts
    var lastBar = ""
    var checking = false     // an update check or install is running

    var paused: Bool { defaults.bool(forKey: "onlyWhileClaude") && !claudeRunning }
    /// The checked Claude Code folder. "" is ~/.claude.
    var profile: String { defaults.string(forKey: "profile") ?? "" }
    var allProfiles: [String] { [""] + (defaults.stringArray(forKey: "profiles") ?? []) }
    /// The profiles in the bar: every one with Multiple users, else the checked one.
    var shown: [String] { defaults.string(forKey: "users") == "multiple" ? allProfiles : [profile] }
    // The menu shows the checked profile's readings.
    var usage: Usage? { accounts[profile]?.usage }
    var updated: Date? { accounts[profile]?.updated }
    var failedAt: Date? { accounts[profile]?.failedAt }
    var problem: String? { accounts[profile]?.problem }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["interval": 180, "showFable": true, "showPace": false, "showBudget": false, "showResets": false, "onlyWhileClaude": true,
                                     "menuBar": "both", "icon": "app", "speedColors": "day", "workHours": 8, "updateEvery": 604800,
                                     "notifyReached": true, "notifyReset": true, "notifyWeek": true,
                                     "loadingIcon": true, "loadingText": false, "showDetails": true, "showProfile": false, "users": "single"])
        // 150 seconds and pace warnings off are no longer options.
        if defaults.integer(forKey: "interval") == 150 { defaults.removeObject(forKey: "interval") }
        if defaults.string(forKey: "speedColors") == "off" { defaults.removeObject(forKey: "speedColors") }
        allProfiles.forEach(load)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        UNUserNotificationCenter.current().delegate = self

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        claudeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: claudeID).isEmpty
        log.notice("start, watching \(self.claudeID, privacy: .public), running: \(self.claudeRunning, privacy: .public)")
        reschedule()
        watchSessions()
        render()

        // The countdowns on the line move between refreshes, and while paused.
        let minute = Timer(timeInterval: 60, target: self, selector: #selector(render), userInfo: nil, repeats: true)
        minute.tolerance = 10
        RunLoop.main.add(minute, forMode: .common)

        let updates = Timer(timeInterval: 3600, target: self, selector: #selector(autoCheck), userInfo: nil, repeats: true)
        updates.tolerance = 600
        RunLoop.main.add(updates, forMode: .common)
        autoCheck()
        Task { showUpdateComplete() }  // after launch finishes, not in the middle of it
        if defaults.bool(forKey: "testNotifications") { testNotifications() }
    }

    @objc func appsChanged(_ note: Notification) {
        guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == claudeID else { return }
        let wasPaused = paused
        claudeRunning = note.name == NSWorkspace.didLaunchApplicationNotification
        log.notice("claude \(self.claudeRunning ? "launched" : "quit", privacy: .public)")
        if paused != wasPaused { reschedule() }
        render()
    }

    // One history per profile, so pace and notices never compare two accounts. ~/.claude keeps the key it always had.
    func historyKey(_ profile: String) -> String { profile.isEmpty ? "history" : "history-\(profile)" }

    func load(_ profile: String) {
        accounts[profile] = Account(samples: (try? JSONDecoder().decode([Sample].self, from: defaults.data(forKey: historyKey(profile)) ?? Data())) ?? [])
    }

    /// After the checked profile, Multiple users or the list changed.
    func profilesChanged() {
        log.notice("shown: \(self.shown.map(profileName), privacy: .public)")
        watchSessions()
        reschedule()
        render()
    }

    /// Refresh now, then every interval. While paused there is no timer, so no requests.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !paused else { return log.notice("paused") }
        tick()
        let timer = Timer(timeInterval: TimeInterval(defaults.integer(forKey: "interval")), target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc func tick() {
        guard !busy, !paused else { return }
        busy = true
        let asked = shown
        Task {
            for profile in asked {
                let result = await fetchUsage(configDir: profile.isEmpty ? nil : profile)
                // Removed or no longer shown while it asked.
                guard shown.contains(profile) else { continue }
                apply(result, to: profile)
                render()
            }
            busy = false
            // Checked or added meanwhile: those still need asking.
            if shown != asked { tick() }
        }
    }

    func apply(_ result: UsageResult, to profile: String) {
        var account = accounts[profile] ?? Account()
        account.usage = nil
        account.problem = nil
        switch result {
        case .ok(let reply):
            let fresh = keepSeverity(reply, from: account.samples.last?.usage)
            post(labeled(notices(from: account.samples.last?.usage, to: fresh, now: .now), profile), settings: defaults)
            account.usage = fresh; account.updated = .now; account.failedAt = nil
            account.samples.append(Sample(at: .now, usage: fresh))
            // speed() needs the newest reading from before its window, so keep one older than a day.
            while account.samples.count > 1, account.samples[1].at <= Date.now.addingTimeInterval(-86400) { account.samples.removeFirst() }
            defaults.set(try? JSONEncoder().encode(account.samples), forKey: historyKey(profile))
        case .notFound: account.problem = "not_found"
        case .signedOut: account.problem = "signed_out"
        case .failed: account.failedAt = .now
        }
        if let problem = account.problem { log.notice("\(profileName(profile), privacy: .public): \(problem, privacy: .public)") }
        accounts[profile] = account
    }

    /// With several profiles each notice says whose it is, and has its own id so one can't replace another's.
    /// ~/.claude keeps its ids, so its notices still replace the ones from before.
    func labeled(_ found: [Notice], _ profile: String) -> [Notice] {
        guard allProfiles.count > 1 else { return found }
        return found.map { notice in
            var notice = notice
            notice.title = "\(profileName(profile)) · \(notice.title)"
            if !profile.isEmpty { notice.id += "-\(profile)" }
            return notice
        }
    }

    func pacing(_ now: Date, _ profile: String? = nil) -> (session: Rate, week: Rate) {
        let account = accounts[profile ?? self.profile]
        return paces(account?.usage, samples: account?.samples ?? [], colors: defaults.string(forKey: "speedColors") ?? "day",
                     workHours: Double(defaults.integer(forKey: "workHours")), now: now)
    }

    @objc func render() {
        let now = Date.now, shown = shown, rates = shown.map { pacing(now, $0) }, mode = defaults.string(forKey: "menuBar")
        let alert = shown.lazy.compactMap { warning(self.accounts[$0]?.usage) }.first
        let pace = (session: rates.map(\.session.pace).max() ?? .ok, week: rates.map(\.week.pace).max() ?? .ok)
        // Multiple users: each profile's numbers in turn.
        let bar = joined(zip(shown, rates).map { profile, rate in
            barText(accounts[profile]?.usage, rates: rate, showFable: defaults.bool(forKey: "showFable"),
                    showPace: defaults.bool(forKey: "showPace"), showBudget: defaults.bool(forKey: "showBudget"),
                    resetsFrom: defaults.bool(forKey: "showResets") ? now : nil,
                    profile: defaults.bool(forKey: "showProfile") ? profileName(profile) : nil)
        })
        guard let button = item.button else { return }
        let tint = mode == "icon" ? max(pace.session, pace.week).color : nil
        func warningIcon() -> NSImage? {
            var image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: alert)
            if let tint {
                // The menu bar draws template images in its own color and ignores contentTintColor.
                // One color per symbol layer: the "!" stays white.
                image = image?.withSymbolConfiguration(.init(paletteColors: [.white, tint]))
                image?.isTemplate = false
            }
            // Centred as a whole, the triangle sits 1.5 points below the numbers.
            return redrawn(image, lift: 1.5)
        }
        let appIcon = NSApp.applicationIconImage.copy() as? NSImage
        appIcon?.size = NSSize(width: 18, height: 18)
        let image = alert != nil ? warningIcon()
            : mode == "numbers" ? nil
            : defaults.string(forKey: "icon") == "app" ? appIcon : star(tint)
        let title = mode == "icon" ? NSAttributedString() : bar
        // While Claude Code writes a reply: 100% to 40% opacity and back every 1.5 seconds.
        // A session quiet for 10 minutes has stopped, however its transcript ends.
        let thinking = midReply.values.contains { now.timeIntervalSince($0) < 600 }
        let fadeIcon = thinking && mode != "numbers" && defaults.bool(forKey: "loadingIcon")
        let fadeText = thinking && mode != "icon" && defaults.bool(forKey: "loadingText")
        let alpha = 0.7 + 0.3 * cos(now.timeIntervalSinceReferenceDate * 2 * .pi / 1.5)
        button.image = fadeIcon ? redrawn(image, alpha: alpha) : image
        button.attributedTitle = fadeText ? faded(title, alpha) : title
        button.imagePosition = mode == "icon" ? .imageOnly : .imageLeading
        button.appearsDisabled = paused
        if (fadeIcon || fadeText) != (pulse != nil) {
            pulse?.invalidate()
            pulse = fadeIcon || fadeText ? Timer(timeInterval: 0.05, target: self, selector: #selector(render), userInfo: nil, repeats: true) : nil
            if let pulse { RunLoop.main.add(pulse, forMode: .common) }
        }
        let line = (alert.map { "⚠ \($0) · " } ?? "") + bar.string + " · pace S \(pace.session) W \(pace.week)"
            + (thinking ? " · thinking" : "") + (paused ? " (paused)" : "")
        if line != lastBar { log.notice("bar: \(line, privacy: .public)") }
        lastBar = line
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
