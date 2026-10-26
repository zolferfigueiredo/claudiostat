import AppKit
import ClaudioStatStrings
import UserNotifications
import os

let log = Logger(subsystem: "com.zolfer.claudiostat", category: "app")

/// One profile's readings.
struct Account {
    var usage: Usage?        // nil after a failed fetch: dashes, never stale numbers
    var samples: [Sample] = []
    var updated: Date?
    var failedAt: Date?
    var problem: String?     // Claude Code missing, signed out or turned away
    var blockedUntil: Date?  // turned away: not asked again before then, unless by Refresh
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    // Launch argument `-watchBundleID com.apple.TextEdit` tests pause/resume without quitting Claude.
    lazy var claudeID = defaults.string(forKey: "watchBundleID") ?? "com.anthropic.claudefordesktop"

    var accounts: [String: Account] = [:]  // by profile
    var claudeRunning = false   // the Claude app
    var codeRunning = false     // Claude Code, in a terminal or in the Claude app
    var busy = false
    var timer: Timer?
    var pulse: Timer?        // redraws the icon or numbers while they fade
    var midReply: [String: Date] = [:]  // Claude Code transcripts mid-reply, by when they were last written
    var sessions: FSEventStreamRef?  // watches the shown profiles' transcripts and ~/.claude's
    var lastBar = ""
    var checking = false     // an update check or install is running
    var awaitingReopen = false  // the setup window asks to reopen, so the bar holds back the numbers until then
    var sharedWithWidget: [String: String] = [:]  // what the desktop widget was last given
    var changedAt = Date.now  // the last reading whose numbers moved

    // Without the Claude app or Claude Code there is nothing to wait for.
    var paused: Bool { defaults.bool(forKey: "onlyWhileClaude") && claudeInstalled && !claudeRunning && !codeRunning }
    lazy var claudeInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeID) != nil || claudePath() != nil
    /// The first Claude Code folder in the bar, whose status the menu shows. "" is ~/.claude.
    var profile: String { shown.first ?? "" }
    var allProfiles: [String] { defaults.stringArray(forKey: "profileList") ?? [] }
    /// The profiles in the bar: the ones switched on in Settings, else the first.
    var shown: [String] { shownProfiles(allProfiles, on: defaults.stringArray(forKey: "shownProfiles") ?? []) }
    // The menu shows the checked profile's readings.
    var usage: Usage? { accounts[profile]?.usage }
    var updated: Date? { accounts[profile]?.updated }
    var failedAt: Date? { accounts[profile]?.failedAt }
    var problem: String? { accounts[profile]?.problem }

    /// Every setting with its default. The bar screenshots test checks each one is in them or marked as not on the bar.
    static let settings: [String: Any] = ["interval": 180, "showPace": false, "showBudget": false, "showResets": false, "onlyWhileClaude": false,
                                          "menuBar": "both", "icon": "app", "speedColors": "day", "workHours": 8, "updateEvery": 604800,
                                          "notifyReached": true, "notifyReset": true, "notifyWeek": true,
                                          "loadingIcon": true, "loadingText": false, "showDetails": true, "showProfile": false,
                                          "detailsLayout": "blocks", "compactText": true, "background": false]

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: Self.settings)
        // `defaults write` from elsewhere (Hammerspoon, a script) changes these too: the bar follows at once, not at its
        // next redraw. The app's own picks redraw twice, which is harmless.
        for key in Self.barLook { defaults.addObserver(self, forKeyPath: key, context: nil) }
        // 30 and 150 seconds and pace warnings off are no longer options.
        if [30, 150].contains(defaults.integer(forKey: "interval")) { defaults.removeObject(forKey: "interval") }
        if defaults.string(forKey: "speedColors") == "off" { defaults.removeObject(forKey: "speedColors") }
        // Before 0.4.1 ~/.claude was always a profile and "profiles" held the others. It stays once it had numbers.
        if defaults.object(forKey: "profileList") == nil {
            defaults.set((defaults.object(forKey: "history") == nil ? [] : [""]) + (defaults.stringArray(forKey: "profiles") ?? []),
                         forKey: "profileList")
        }
        // Before 0.10.0 the bar showed every profile with Multiple users, else the checked one.
        if defaults.object(forKey: "shownProfiles") == nil {
            let checked = defaults.string(forKey: "profile")
            defaults.set(defaults.string(forKey: "users") == "multiple" ? allProfiles : allProfiles.filter { $0 == checked },
                         forKey: "shownProfiles")
            defaults.removeObject(forKey: "users")
            defaults.removeObject(forKey: "profile")
        }
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
        codeRunning = claudeCodeRunning()
        log.notice("start, watching \(self.claudeID, privacy: .public), running: \(self.claudeRunning, privacy: .public), Claude Code: \(self.codeRunning, privacy: .public)")
        reschedule()
        watchSessions()
        render()
        if allProfiles.isEmpty { addProfile() }
        Task {
            for path in allProfiles { await refreshName(path) }
            render()
        }

        // The countdowns on the line move between refreshes, and while paused.
        let minute = Timer(timeInterval: 60, target: self, selector: #selector(everyMinute), userInfo: nil, repeats: true)
        minute.tolerance = 10
        RunLoop.main.add(minute, forMode: .common)

        let updates = Timer(timeInterval: 3600, target: self, selector: #selector(autoCheck), userInfo: nil, repeats: true)
        updates.tolerance = 600
        RunLoop.main.add(updates, forMode: .common)
        autoCheck()
        Task { showUpdateComplete() }  // after launch finishes, not in the middle of it
        if defaults.bool(forKey: "testNotifications") { testNotifications() }
    }

    /// The settings that only change how the bar looks.
    static let barLook = ["menuBar", "icon", "compactText", "background", "showPace", "showBudget", "showResets", "showProfile",
                          "loadingIcon", "loadingText", "speedColors"]

    // It can arrive off the main thread.
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                           context: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            log.notice("\(keyPath ?? "", privacy: .public) changed")
            render()
            shareWithWidget()
        }
    }

    @objc func appsChanged(_ note: Notification) {
        guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == claudeID else { return }
        let wasPaused = paused
        claudeRunning = note.name == NSWorkspace.didLaunchApplicationNotification
        log.notice("claude \(self.claudeRunning ? "launched" : "quit", privacy: .public)")
        if paused != wasPaused { reschedule() }
        render()
    }

    /// Claude Code in a terminal starts and quits without a notification, so it is looked for every minute and when the menu opens.
    func lookForClaudeCode() {
        let wasPaused = paused
        codeRunning = claudeCodeRunning()
        guard paused != wasPaused else { return }
        log.notice("claude code \(self.codeRunning ? "running" : "closed", privacy: .public)")
        reschedule()
    }

    @objc func everyMinute() {
        lookForClaudeCode()
        render()
    }

    // One history per profile, so pace and notices never compare two accounts. ~/.claude keeps the key it always had.
    func historyKey(_ profile: String) -> String { profile.isEmpty ? "history" : "history-\(profile)" }

    func load(_ profile: String) {
        accounts[profile] = Account(samples: (try? JSONDecoder().decode([Sample].self, from: defaults.data(forKey: historyKey(profile)) ?? Data())) ?? [])
    }

    /// After a profile was switched on or off, added or removed.
    func profilesChanged() {
        log.notice("shown: \(self.shown.map(folderName), privacy: .public)")
        watchSessions()
        reschedule()
        render()
        shareWithWidget()
    }

    /// Refresh now, then every interval. While paused there is no timer, so no requests.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !paused else { return log.notice("paused") }
        tick()
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        let every = refreshEvery(TimeInterval(defaults.integer(forKey: "interval")), quiet: Date.now.timeIntervalSince(changedAt))
        let timer = Timer(timeInterval: every, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc func tick() {
        guard !busy, !paused else { return }
        busy = true
        let asked = shown
        Task {
            for profile in asked where accounts[profile]?.blockedUntil ?? .distantPast <= .now {
                let result = await fetchUsage(configDir: profile.isEmpty ? nil : profile)
                // Removed or no longer shown while it asked.
                guard shown.contains(profile) else { continue }
                apply(result, to: profile)
                render()
            }
            busy = false
            shareWithWidget()
            if let timer, timer.timeInterval != refreshEvery(TimeInterval(defaults.integer(forKey: "interval")),
                                                              quiet: Date.now.timeIntervalSince(changedAt)) { startTimer() }
            // Checked or added meanwhile: those still need asking.
            if shown != asked { tick() }
        }
    }

    /// Refresh in the menu asks the profiles Claude turned away too.
    @objc func refreshNow() {
        for profile in shown { accounts[profile]?.blockedUntil = nil }
        tick()
    }

    func apply(_ result: UsageResult, to profile: String) {
        var account = accounts[profile] ?? Account()
        let last = account.usage
        account.usage = nil
        account.problem = nil
        account.blockedUntil = nil
        switch result {
        case .ok(let reply):
            let fresh = keepSeverity(reply, from: account.samples.last?.usage)
            let old = account.samples.last?.usage
            if [fresh.session?.percent, fresh.week?.percent, fresh.fable?.percent] != [old?.session?.percent, old?.week?.percent, old?.fable?.percent] {
                changedAt = .now
            }
            post(labeled(notices(from: account.samples.last?.usage, to: fresh, now: .now), profile), settings: defaults)
            account.usage = fresh; account.updated = .now; account.failedAt = nil
            account.samples.append(Sample(at: .now, usage: fresh))
            // speed() needs the newest reading from before its window, so keep one older than a day.
            while account.samples.count > 1, account.samples[1].at <= Date.now.addingTimeInterval(-86400) { account.samples.removeFirst() }
            defaults.set(try? JSONEncoder().encode(account.samples), forKey: historyKey(profile))
        case .notFound: account.problem = "not_found"
        case .signedOut: account.problem = "signed_out"
        case .rateLimited:
            // Claude turns this login away for about 20 minutes: wait that out with the last numbers, faded.
            // Signing in again gets a new login, which it doesn't turn away.
            account.usage = last; account.problem = "rate_limited"; account.blockedUntil = .now.addingTimeInterval(25 * 60)
        case .failed: account.failedAt = .now
        }
        if let problem = account.problem { log.notice("\(folderName(profile), privacy: .public): \(problem, privacy: .public)") }
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

    @objc func render() { render(at: .now) }

    /// The bar at `now`: the bar screenshots pass a fixed time.
    func render(at now: Date) {
        let shown = shown
        // Until Reopen, the icon alone: numbers already there would make Reopen look pointless.
        let counted = awaitingReopen ? [] : shown, rates = counted.map { pacing(now, $0) }
        let alert = counted.lazy.compactMap { warning(self.accounts[$0]?.usage) }.first
        let pace = (session: rates.map(\.session.pace).max() ?? .ok, week: rates.map(\.week.pace).max() ?? .ok)
        let speed = defaults.bool(forKey: "showPace"), budget = defaults.bool(forKey: "showBudget")
        let resets = defaults.bool(forKey: "showResets") ? now : nil, names = defaults.bool(forKey: "showProfile")
        // Turned away by Claude: the last numbers, faded like a pause.
        func last(_ profile: String, _ text: NSAttributedString) -> NSAttributedString {
            accounts[profile]?.blockedUntil == nil ? text : faded(text, 0.5)
        }
        // Several profiles on: each one's numbers in turn.
        let bar = joined(zip(counted, rates).map { profile, rate in
            last(profile, barText(accounts[profile]?.usage, rates: rate, showPace: speed, showBudget: budget,
                                  resetsFrom: resets, profile: names ? profileName(profile) : nil))
        })
        let compact = !defaults.bool(forKey: "compactText") ? [] : zip(counted, rates).flatMap { profile, rate in
            compactText(accounts[profile]?.usage, rates: rate, showPace: speed, showBudget: budget,
                        resetsFrom: resets, profile: names ? profileName(profile) : nil).map { $0.map { $0.map { last(profile, $0) } } }
        }
        guard let button = item.button else { return }
        // Nothing to show yet: the icon alone, whatever Display says.
        let mode = bar.length == 0 && !shown.isEmpty ? "icon" : defaults.string(forKey: "menuBar")
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
        // With no profile the bar keeps its icon and asks for one, whatever Display says.
        let image = alert != nil ? warningIcon()
            : mode == "numbers" && !shown.isEmpty ? nil
            : defaults.string(forKey: "icon") == "app" ? appIcon : star(tint)
        let title = shown.isEmpty ? joined([NSAttributedString(string: tr("add_a_profile"))]) : mode == "icon" ? NSAttributedString() : bar
        // While Claude Code writes a reply: 100% to 40% opacity and back every 1.5 seconds.
        // A session quiet for 10 minutes has stopped, however its transcript ends.
        let thinking = midReply.values.contains { now.timeIntervalSince($0) < 600 }
        let fadeIcon = thinking && mode != "numbers" && defaults.bool(forKey: "loadingIcon")
        let fadeText = thinking && mode != "icon" && defaults.bool(forKey: "loadingText")
        let alpha = 0.7 + 0.3 * cos(now.timeIntervalSinceReferenceDate * 2 * .pi / 1.5)
        let icon = fadeIcon ? redrawn(image, alpha: alpha) : image
        let background = defaults.bool(forKey: "background"), spoken = (alert.map { "\($0) · " } ?? "") + bar.string
        if !compact.isEmpty, mode != "icon" {
            // A title has one line, so the two go beside the icon in its image, which appearsDisabled dims whole.
            let lines = twoLines(compact), both = beside(icon, fadeText ? redrawn(lines, alpha: alpha) ?? lines : lines)
            both.accessibilityDescription = spoken
            button.image = background ? backed(both) : both
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        } else {
            // appearsDisabled leaves colored text alone, so paused text is faded to half here.
            let textAlpha = (fadeText ? alpha : 1) * (paused ? 0.5 : 1)
            let text = textAlpha < 1 ? faded(title, textAlpha) : title
            if background {
                // The background goes behind the icon and the text together, so the text goes in the image too.
                let both = text.length == 0 ? icon : beside(icon, oneLine(text))
                if !spoken.isEmpty { both?.accessibilityDescription = spoken }
                button.image = both.map(backed)
                button.attributedTitle = NSAttributedString()
                button.imagePosition = .imageOnly
            } else {
                button.image = icon
                button.attributedTitle = text
                button.imagePosition = mode == "icon" && !shown.isEmpty ? .imageOnly : .imageLeading
            }
        }
        button.appearsDisabled = paused
        if (fadeIcon || fadeText) != (pulse != nil) {
            pulse?.invalidate()
            pulse = fadeIcon || fadeText ? Timer(timeInterval: 0.05, target: self, selector: #selector(render as () -> Void), userInfo: nil, repeats: true) : nil
            if let pulse { RunLoop.main.add(pulse, forMode: .common) }
        }
        let line = (alert.map { "⚠ \($0) · " } ?? "") + bar.string + " · pace S \(pace.session) W \(pace.week)"
            + (thinking ? " · thinking" : "") + (paused ? " (paused)" : "")
        if line != lastBar { log.notice("bar: \(line, privacy: .public)") }
        lastBar = line
    }
}

// One copy at a time: the one just opened (the DMG's, a build) takes over from any other.
for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") where other != .current {
    other.terminate()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
