import AppKit
import ServiceManagement

extension AppDelegate {
    // Opening the app again (its Dock shortcut, Spotlight, Finder) shows the menu at the pointer.
    // That also reaches it when the notch hides the menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        item.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return false
    }

    // Rebuilt on every open, so countdowns and the login item state are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date.now, mode = defaults.string(forKey: "menuBar")
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
        func choice(_ title: String, _ key: String, _ value: Any, enabled: Bool = true) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: #selector(choose), keyEquivalent: "")
            entry.target = self
            entry.representedObject = [key: value]
            entry.state = "\(defaults.object(forKey: key) ?? "")" == "\(value)" ? .on : .off
            entry.isEnabled = enabled
            return entry
        }
        func toggle(_ title: String, _ key: String, enabled: Bool = true) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: #selector(toggleSetting), keyEquivalent: "")
            entry.target = self
            entry.representedObject = key
            entry.state = defaults.bool(forKey: key) ? .on : .off
            entry.isEnabled = enabled
            return entry
        }

        // Each group sets one setting, groups split by a line. The `disabled` group is greyed out.
        @discardableResult
        func submenu(_ title: String, _ groups: [(key: String, options: [(value: Any, title: String)])], disabled: String? = nil) -> NSMenuItem {
            let choices = NSMenu()
            choices.autoenablesItems = false
            for (key, options) in groups {
                if choices.numberOfItems > 0 { choices.addItem(.separator()) }
                for (value, name) in options { choices.addItem(choice(name, key, value, enabled: key != disabled)) }
            }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = choices
            menu.addItem(entry)
            return entry
        }

        let details = defaults.bool(forKey: "showDetails")
        action("Show data below", #selector(toggleSetting), on: details).representedObject = "showDetails"
        if details {
            if let alert = warning(usage) { info("⚠ \(alert)") }
            let rate = pacing(now)
            limit("Session", usage?.session, rate.session)
            limit("Week", usage?.week, rate.week)
            limit("Fable", usage?.fable)
            let hourly = rate.week.unit == 3600
            info("Pace (experimental) · \(percent(rate.week.speed))" + (rate.week.speed == nil ? "" : hourly ? " an hour" : " a day"))
            let budgetName = hourly ? "Budget per hour" : "Budget per day"
            if let week = usage?.week, let reset = week.resetsAt, rate.week.needed != nil {
                let left = reset.timeIntervalSince(now)
                // Hourly, the budget divides over working hours only, so show those rather than the wall-clock countdown.
                let over = hourly ? "\(Int((left * Double(defaults.integer(forKey: "workHours")) / 24 / 3600).rounded(.up))) working hours"
                                  : span(left)
                info("\(budgetName) \(percent(rate.week.needed)) · \(max(0, 100 - week.percent))% left over \(over)")
            } else {
                info("\(budgetName) \(percent(rate.week.needed))")
            }
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

        let display = submenu("Display", [("menuBar", [("both", "Icon and numbers"), ("icon", "Icon only"), ("numbers", "Numbers only")]),
                                          ("icon", [("app", "App icon"), ("star", "Plain star icon")])],
                              disabled: mode == "numbers" ? "icon" : nil)
        // They pulse while tokens are being spent. Numbers only has no icon, Icon only no numbers.
        display.submenu?.addItem(.separator())
        display.submenu?.addItem(toggle("Loading icon", "loadingIcon", enabled: mode != "numbers"))
        display.submenu?.addItem(toggle("Loading text", "loadingText", enabled: mode != "icon"))
        // A submenu of on/off settings.
        @discardableResult
        func toggles(_ title: String, _ settings: [(title: String, key: String)]) -> NSMenuItem {
            let choices = NSMenu()
            choices.autoenablesItems = false
            for (name, key) in settings { choices.addItem(toggle(name, key)) }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = choices
            menu.addItem(entry)
            return entry
        }

        // What the menu bar shows after S and W. speedColors is the unit of P and B, which W's color compares.
        let data = toggles("Data", [("Fable", "showFable"), ("Pace (experimental)", "showPace"), ("Budget", "showBudget")])
        data.submenu?.addItem(.separator())
        for (value, name) in [("day", "Budget per day"), ("hour", "Budget per hour")] {
            data.submenu?.addItem(choice(name, "speedColors", value, enabled: defaults.bool(forKey: "showBudget")))
        }
        data.submenu?.addItem(.separator())
        data.submenu?.addItem(toggle("Resets in", "showResets"))
        // Hours a day spent using Claude, so the pace ignores the rest of the day.
        submenu("Daily working time", [("workHours", [24, 16, 12, 8, 6, 4].map { ($0, "\($0) hours") })])
        toggles("Notifications", [("Limit reached", NoticeKind.reached.setting), ("Limit reset", NoticeKind.reset.setting),
                                  ("Week at 80% and 90%", NoticeKind.week.setting)])
        menu.addItem(.separator())
        // Registering from anywhere else (a build folder in /tmp) would point the login item at a bundle that disappears.
        action("Launch at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled,
               enabled: Bundle.main.bundlePath.hasPrefix("/Applications/"))
        action("Keep in Dock", #selector(toggleDock), on: inDock())
        menu.addItem(.separator())
        action("About ClaudioStat", #selector(showAbout)).image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(.separator())
        let check = action("Check for updates…", #selector(checkNow), enabled: !checking)
        if let version = availableUpdate {
            check.attributedTitle = updateAvailableTitle(version)
            check.image = updateAvailableIcon()
        } else {
            check.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        }
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
}
