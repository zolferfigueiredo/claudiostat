import AppKit
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
        Task { showUpdateComplete() }  // after launch finishes, not in the middle of it
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
