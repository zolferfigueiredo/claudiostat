import AppKit
import ServiceManagement
import SwiftUI
import os

let log = Logger(subsystem: "com.zolfer.claudiostat", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    // Launch argument `-watchBundleID com.apple.TextEdit` tests pause/resume without quitting Claude.
    lazy var claudeID = defaults.string(forKey: "watchBundleID") ?? "com.anthropic.claudefordesktop"

    var usage: Usage?        // nil after a failed fetch: dashes, never stale numbers
    var samples: [Sample] = []
    var updated: Date?
    var failedAt: Date?
    var problem: String?     // Claude Code missing or signed out
    var claudeRunning = false
    var busy = false
    var timer: Timer?
    var lastBar = ""
    var checking = false     // an update check or install is running

    var paused: Bool { defaults.bool(forKey: "onlyWhileClaude") && !claudeRunning }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["interval": 180, "showFable": true, "showPace": false, "showBudget": false, "onlyWhileClaude": true,
                                     "menuBar": "both", "icon": "app", "speedColors": "day", "workHours": 8, "updateEvery": 604800])
        // 150 seconds is no longer an option.
        if defaults.integer(forKey: "interval") == 150 { defaults.removeObject(forKey: "interval") }
        samples = (try? JSONDecoder().decode([Sample].self, from: defaults.data(forKey: "history") ?? Data())) ?? []
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        claudeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: claudeID).isEmpty
        log.notice("start, watching \(self.claudeID, privacy: .public), running: \(self.claudeRunning, privacy: .public)")
        reschedule()
        render()

        let updates = Timer(timeInterval: 3600, target: self, selector: #selector(autoCheck), userInfo: nil, repeats: true)
        updates.tolerance = 600
        RunLoop.main.add(updates, forMode: .common)
        autoCheck()
    }

    @objc func appsChanged(_ note: Notification) {
        guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == claudeID else { return }
        let wasPaused = paused
        claudeRunning = note.name == NSWorkspace.didLaunchApplicationNotification
        log.notice("claude \(self.claudeRunning ? "launched" : "quit", privacy: .public)")
        if paused != wasPaused { reschedule() }
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
        Task {
            let result = await fetchUsage()
            usage = nil
            problem = nil
            switch result {
            case .ok(let reply):
                let fresh = keepSeverity(reply, from: samples.last?.usage)
                usage = fresh; updated = .now; failedAt = nil
                samples.append(Sample(at: .now, usage: fresh))
                // speed() needs the newest reading from before its window, so keep one older than a day.
                while samples.count > 1, samples[1].at <= Date.now.addingTimeInterval(-86400) { samples.removeFirst() }
                defaults.set(try? JSONEncoder().encode(samples), forKey: "history")
            case .notFound: problem = "Claude Code not found"
            case .signedOut: problem = "Sign in to Claude Code first (run claude)"
            case .failed: failedAt = .now
            }
            if let problem { log.notice("\(problem, privacy: .public)") }
            busy = false
            render()
        }
    }

    func pacing(_ now: Date) -> (session: Rate, week: Rate) {
        paces(usage, samples: samples, colors: defaults.string(forKey: "speedColors") ?? "day",
              workHours: Double(defaults.integer(forKey: "workHours")), now: now)
    }

    func render() {
        let now = Date.now, rate = pacing(now), mode = defaults.string(forKey: "menuBar"), alert = warning(usage)
        let pace = (session: rate.session.pace, week: rate.week.pace)
        let bar = barText(usage, rates: rate, showFable: defaults.bool(forKey: "showFable"),
                          showPace: defaults.bool(forKey: "showPace"), showBudget: defaults.bool(forKey: "showBudget"))
        guard let button = item.button else { return }
        let tint = mode == "icon" ? max(pace.session, pace.week).color : nil
        func warningIcon() -> NSImage? {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: alert)
            guard let tint else { return image }
            // The menu bar draws template images in its own color and ignores contentTintColor.
            // One color per symbol layer: the "!" stays white.
            let colored = image?.withSymbolConfiguration(.init(paletteColors: [.white, tint]))
            colored?.isTemplate = false
            return colored
        }
        let appIcon = NSApp.applicationIconImage.copy() as? NSImage
        appIcon?.size = NSSize(width: 18, height: 18)
        button.image = alert != nil ? warningIcon()
            : mode == "numbers" ? nil
            : defaults.string(forKey: "icon") == "app" ? appIcon : star(tint)
        button.attributedTitle = mode == "icon" ? NSAttributedString() : bar
        button.imagePosition = mode == "icon" ? .imageOnly : .imageLeading
        button.appearsDisabled = paused
        let line = (alert.map { "⚠ \($0) · " } ?? "") + bar.string + " · pace S \(pace.session) W \(pace.week)" + (paused ? " (paused)" : "")
        if line != lastBar { log.notice("bar: \(line, privacy: .public)") }
        lastBar = line
    }

    // Rebuilt on every open, so countdowns and the login item state are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date.now
        func info(_ text: String, _ color: NSColor? = nil) {
            let line = NSMenuItem()
            line.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: color ?? NSColor.labelColor])
            line.isEnabled = false
            menu.addItem(line)
        }
        func limit(_ name: String, _ value: Limit?, _ rate: Rate? = nil) {
            let color = rate?.pace.color
            info("\(name) \(percent(value?.percent))" + (value?.resetsAt.map { " · resets in \(span($0.timeIntervalSince(now)))" } ?? ""), color)
            if let reason = rate?.reason { info(reason, color) }
        }
        @discardableResult
        func action(_ title: String, _ selector: Selector, key: String = "", on: Bool = false, enabled: Bool = true) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            entry.target = self
            entry.state = on ? .on : .off
            entry.isEnabled = enabled
            menu.addItem(entry)
            return entry
        }

        // Each group sets one setting, groups split by a line. The `disabled` group is greyed out.
        @discardableResult
        func submenu(_ title: String, _ groups: [(key: String, options: [(value: Any, title: String)])], disabled: String? = nil) -> NSMenuItem {
            let choices = NSMenu()
            choices.autoenablesItems = false
            for (key, options) in groups {
                if choices.numberOfItems > 0 { choices.addItem(.separator()) }
                for (value, name) in options {
                    let choice = NSMenuItem(title: name, action: #selector(choose), keyEquivalent: "")
                    choice.target = self
                    choice.representedObject = [key: value]
                    choice.state = "\(defaults.object(forKey: key) ?? "")" == "\(value)" ? .on : .off
                    choice.isEnabled = key != disabled
                    choices.addItem(choice)
                }
            }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = choices
            menu.addItem(entry)
            return entry
        }

        let rate = pacing(now)
        if let alert = warning(usage) { info("⚠ \(alert)") }
        limit("Session", usage?.session, rate.session)
        limit("Week", usage?.week, rate.week)
        limit("Fable", usage?.fable)
        let budgetName = rate.week.unit == 3600 ? "Hourly budget" : "Daily budget"
        if let week = usage?.week, let reset = week.resetsAt, rate.week.needed != nil {
            info("\(budgetName) \(percent(rate.week.needed)) · \(max(0, 100 - week.percent))% left over \(span(reset.timeIntervalSince(now)))")
        } else {
            info("\(budgetName) \(percent(rate.week.needed))")
        }
        menu.addItem(.separator())

        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        let status: String
        if paused { status = "Paused · Claude isn't open" + (updated.map { " · updated \(time($0))" } ?? "") }
        else if let problem { status = problem }
        else if let failedAt { status = "Update failed \(time(failedAt))" }
        else { status = updated.map { "Updated \(time($0))" } ?? "Updating…" }
        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        action("Refresh now", #selector(tick), key: "r", enabled: !paused && !busy)

        submenu("Refresh every", [("interval", [(60, "1 minute"), (180, "3 minutes"), (300, "5 minutes"), (600, "10 minutes")])])
        action("Only refresh while Claude is open", #selector(toggleSetting), on: defaults.bool(forKey: "onlyWhileClaude"))
            .representedObject = "onlyWhileClaude"
        action("Claude Status", #selector(openStatus))
        menu.addItem(.separator())

        submenu("Display", [("menuBar", [("both", "Icon and numbers"), ("icon", "Icon only"), ("numbers", "Numbers only")]),
                            ("icon", [("app", "App icon"), ("star", "Plain star icon")])],
                disabled: defaults.string(forKey: "menuBar") == "numbers" ? "icon" : nil)
        // What the menu bar shows after S and W.
        let data = NSMenu()
        for (title, key) in [("Fable", "showFable"), ("Pace (experimental)", "showPace"), ("Budget", "showBudget")] {
            let toggle = NSMenuItem(title: title, action: #selector(toggleSetting), keyEquivalent: "")
            toggle.target = self
            toggle.state = defaults.bool(forKey: key) ? .on : .off
            toggle.representedObject = key
            data.addItem(toggle)
        }
        let dataEntry = NSMenuItem(title: "Data", action: nil, keyEquivalent: "")
        dataEntry.submenu = data
        menu.addItem(dataEntry)
        submenu("Pace warning mode", [("speedColors", [("day", "W per day"), ("hour", "W per hour"), ("off", "Off")])])
        // Hours a day spent using Claude, so the pace ignores the rest of the day.
        submenu("Working time", [("workHours", [24, 16, 12, 8, 6, 4].map { ($0, "\($0) hours") })])
        menu.addItem(.separator())
        // Registering from anywhere else (a build folder in /tmp) would point the login item at a bundle that disappears.
        action("Launch at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled,
               enabled: Bundle.main.bundlePath.hasPrefix("/Applications/"))
        action("Keep in Dock", #selector(toggleDock), on: inDock())
        menu.addItem(.separator())
        action("About ClaudioStat", #selector(showAbout)).image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(.separator())
        action("Check for updates…", #selector(checkNow), enabled: !checking).image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        // A blank image lines the title up with the icon rows.
        submenu("Check automatically", [("updateEvery", [(86400, "Daily"), (604800, "Weekly"), (0, "Never")])]).image = NSImage(size: NSSize(width: 16, height: 16))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClaudioStat", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: nil)
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let pick = (sender.representedObject as? [String: Any])?.first else { return }
        defaults.set(pick.value, forKey: pick.key)
        log.notice("\(pick.key, privacy: .public) = \(String(describing: pick.value), privacy: .public)")
        if pick.key == "interval" { reschedule() }
        render()
    }

    @objc func autoCheck() {
        let every = TimeInterval(defaults.integer(forKey: "updateEvery"))
        guard updateCheckIsDue(last: defaults.object(forKey: "lastUpdateCheck") as? Date, every: every, now: .now) else { return }
        checkForUpdates(quiet: true)
    }

    @objc func checkNow() { checkForUpdates(quiet: false) }

    /// Quiet checks only speak up when there is a new version.
    func checkForUpdates(quiet: Bool) {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            guard let latest = await latestVersion() else {
                log.notice("update check failed")
                if !quiet { alert("Couldn't check for updates", "Check your connection and try again.") }
                return
            }
            defaults.set(Date.now, forKey: "lastUpdateCheck")
            log.notice("latest \(latest, privacy: .public), running \(appVersion, privacy: .public)")
            guard isNewer(latest, than: appVersion) else {
                if !quiet { alert("You're up to date", "ClaudioStat \(appVersion) is the latest version.") }
                return
            }
            guard alert("ClaudioStat \(latest) is available", "You have \(appVersion). Update now?", "Update Now", "Later") else { return }
            do {
                guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
                    throw UpdateError(errorDescription: "ClaudioStat updates itself only when it runs from the Applications folder.")
                }
                try await install(latest)
                let relaunch = NSWorkspace.OpenConfiguration()
                relaunch.createsNewApplicationInstance = true
                try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: relaunch)
                NSApp.terminate(nil)
            } catch {
                log.error("update: \(error.localizedDescription, privacy: .public)")
                if alert("Couldn't install the update", error.localizedDescription, "Download", "Cancel") {
                    NSWorkspace.shared.open(dmgURL(latest))
                }
            }
        }
    }

    /// True when the first button was clicked.
    @discardableResult
    func alert(_ title: String, _ text: String, _ buttons: String...) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        log.notice("\(key, privacy: .public) = \(self.defaults.bool(forKey: key), privacy: .public)")
        if key == "onlyWhileClaude" { reschedule() }
        render()
    }

    @objc func toggleDock() { toggleDockTile() }

    @objc func openStatus() {
        NSWorkspace.shared.open(URL(string: "https://status.claude.com/")!)
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    lazy var about: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.styleMask = [.titled, .closable]
        window.title = "About ClaudioStat"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // The hosting controller only sizes the window once shown, too late for center().
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        return window
    }()

    @objc func showAbout() {
        NSApp.activate()
        about.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        HStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("ClaudioStat").font(.title2.bold())
                HStack(spacing: 4) {
                    Text("By")
                    Link("Zolfer Figueiredo", destination: URL(string: "https://zolfer.com/")!)
                }
                Text("Version \(appVersion)")
                Link("Website", destination: URL(string: "https://claudiostat.zolfer.com/")!)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .fixedSize()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
