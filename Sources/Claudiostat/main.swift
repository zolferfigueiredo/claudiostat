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

    var paused: Bool { defaults.bool(forKey: "onlyWhileClaude") && !claudeRunning }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["interval": 150, "showFable": true, "showBudget": false, "onlyWhileClaude": true,
                                     "menuBar": "both", "icon": "star", "speedColors": "day"])
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

    func pacing(_ now: Date) -> (session: Pace, week: Pace) {
        paces(usage, samples: samples, colors: defaults.string(forKey: "speedColors") ?? "day", now: now)
    }

    func render() {
        let now = Date.now, pace = pacing(now), mode = defaults.string(forKey: "menuBar"), alert = warning(usage)
        let bar = barText(usage, paces: pace, showFable: defaults.bool(forKey: "showFable"),
                          showBudget: defaults.bool(forKey: "showBudget"), now: now)
        guard let button = item.button else { return }
        let tint = mode == "icon" ? max(pace.session, pace.week).color : nil
        func symbol(_ name: String) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: alert ?? "Claudiostat")
            guard let tint else { return image }
            // The menu bar draws template images in its own color and ignores contentTintColor.
            // One color per symbol layer: the triangle's "!" stays white.
            let colored = image?.withSymbolConfiguration(.init(paletteColors: name == "star.fill" ? [tint] : [.white, tint]))
            colored?.isTemplate = false
            return colored
        }
        let appIcon = NSApp.applicationIconImage.copy() as? NSImage
        appIcon?.size = NSSize(width: 18, height: 18)
        button.image = alert != nil ? symbol("exclamationmark.triangle.fill")
            : mode == "numbers" ? nil
            : defaults.string(forKey: "icon") == "app" ? appIcon : symbol("star.fill")
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
        func limit(_ name: String, _ value: Limit?, _ pace: Pace = .ok) {
            info("\(name) \(percent(value?.percent))" + (value?.resetsAt.map { " · resets in \(span($0.timeIntervalSince(now)))" } ?? ""), pace.color)
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

        // Each group sets one setting, groups split by a line.
        func submenu(_ title: String, _ groups: [(key: String, options: [(value: Any, title: String)])]) {
            let choices = NSMenu()
            for (key, options) in groups {
                if choices.numberOfItems > 0 { choices.addItem(.separator()) }
                for (value, name) in options {
                    let choice = NSMenuItem(title: name, action: #selector(choose), keyEquivalent: "")
                    choice.target = self
                    choice.representedObject = [key: value]
                    choice.state = "\(defaults.object(forKey: key) ?? "")" == "\(value)" ? .on : .off
                    choices.addItem(choice)
                }
            }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = choices
            menu.addItem(entry)
        }

        let pace = pacing(now)
        if let alert = warning(usage) { info("⚠ \(alert)") }
        limit("Session", usage?.session, pace.session)
        limit("Week", usage?.week, pace.week)
        limit("Fable", usage?.fable)
        if let week = usage?.week, let reset = week.resetsAt, let daily = budget(usage, now: now) {
            info("Daily budget \(daily)% · \(max(0, 100 - week.percent))% left over \(span(reset.timeIntervalSince(now)))")
        } else {
            info("Daily budget \(percent(budget(usage, now: now)))")
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

        submenu("Refresh every", [("interval", [(150, "150 seconds"), (300, "5 minutes"), (600, "10 minutes")])])
        menu.addItem(.separator())

        submenu("Menu bar", [("menuBar", [("both", "Icon and numbers"), ("icon", "Icon only"), ("numbers", "Numbers only")]),
                             ("icon", [("star", "Plain star"), ("app", "App icon")])])
        submenu("Speed colors", [("speedColors", [("day", "W per day"), ("hour", "W per hour"), ("off", "Off")])])
        for (title, key) in [("Show Fable in menu bar", "showFable"), ("Show daily budget in menu bar", "showBudget"),
                             ("Only refresh while Claude is open", "onlyWhileClaude")] {
            action(title, #selector(toggleSetting), on: defaults.bool(forKey: key)).representedObject = key
        }
        // Registering from anywhere else (a build folder in /tmp) would point the login item at a bundle that disappears.
        action("Launch at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled,
               enabled: Bundle.main.bundlePath.hasPrefix("/Applications/"))
        menu.addItem(.separator())
        action("About Claudiostat", #selector(showAbout))
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
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

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        log.notice("\(key, privacy: .public) = \(self.defaults.bool(forKey: key), privacy: .public)")
        if key == "onlyWhileClaude" { reschedule() }
        render()
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
        window.title = "About Claudiostat"
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
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"

    var body: some View {
        HStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("Claudiostat").font(.title2.bold())
                HStack(spacing: 4) {
                    Text("By")
                    Link("Zolfer Figueiredo", destination: URL(string: "https://zolfer.com/")!)
                }
                Text("Version \(version)")
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
