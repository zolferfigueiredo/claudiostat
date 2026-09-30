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
            let used = "\(name) \(percent(value?.percent))"
            info(value?.resetsAt.map { tr("resets", ["limit": used, "time": span($0.timeIntervalSince(now))]) } ?? used, color)
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
        action(tr("show_data"), #selector(toggleSetting), on: details).representedObject = "showDetails"
        if details {
            if let alert = warning(usage) { info("⚠ \(alert)") }
            let rate = pacing(now)
            // Other languages' words needn't start with the bar's letter (W is "Semana"), so each line starts with it.
            let letter = { (letter: String, key: String) in Language.current == .en ? tr(key) : "\(letter) · \(tr(key))" }
            limit(letter("S", "session"), usage?.session, rate.session)
            limit(letter("W", "week"), usage?.week, rate.week)
            limit(letter("F", "fable"), usage?.fable)
            let hourly = rate.week.unit == 3600
            let speed = percent(rate.week.speed)
            info("\(letter("P", "pace_experimental")) · " + (rate.week.speed == nil ? speed : tr(hourly ? "rate_hour" : "rate_day", ["n": speed])))
            let budgetName = letter("B", hourly ? "budget_hour" : "budget_day")
            if let week = usage?.week, let reset = week.resetsAt, rate.week.needed != nil {
                let left = reset.timeIntervalSince(now)
                // Hourly, the budget divides over working hours only, so show those rather than the wall-clock countdown.
                let over = hourly ? plural("working_hours", Int((left * Double(defaults.integer(forKey: "workHours")) / 24 / 3600).rounded(.up)))
                                  : span(left)
                info("\(budgetName) \(percent(rate.week.needed)) · " + tr("left_over", ["left": max(0, 100 - week.percent), "time": over]))
            } else {
                info("\(budgetName) \(percent(rate.week.needed))")
            }
        }
        menu.addItem(.separator())

        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        let status: String
        if paused { status = updated.map { tr("paused_updated", ["time": time($0)]) } ?? tr("paused") }
        else if let problem { status = tr(problem) }
        else if let failedAt { status = tr("failed", ["time": time(failedAt)]) }
        else { status = updated.map { tr("updated", ["time": time($0)]) } ?? tr("updating") }
        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        action(tr("refresh"), #selector(tick), key: "r", enabled: !paused && !busy)

        submenu(tr("every"), [("interval", [1, 3, 5, 10].map { ($0 * 60, plural("minutes", $0)) })])
        action(tr("only"), #selector(toggleSetting), on: defaults.bool(forKey: "onlyWhileClaude"))
            .representedObject = "onlyWhileClaude"
        action(tr("status"), #selector(openStatus))
        menu.addItem(.separator())

        // Each profile is a Claude Code folder with its own login. The checked one fills the bar and this menu.
        let profiles = submenu(tr("profile"), [("profile", allProfiles.map { ($0, profileName($0)) })])
        let add = NSMenuItem(title: tr("add_profile"), action: #selector(addProfile), keyEquivalent: "")
        add.target = self
        let remove = NSMenuItem(title: tr("remove_profile"), action: #selector(removeProfile), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = !profile.isEmpty
        for entry in [.separator(), add, remove] { profiles.submenu?.addItem(entry) }

        // "numbers" stays the stored value from before the label became Text only.
        let display = submenu(tr("display"), [("menuBar", [("both", tr("both")), ("icon", tr("icon_only")), ("numbers", tr("text_only"))]),
                                              ("icon", [("app", tr("app_icon")), ("star", tr("star_icon"))])],
                              disabled: mode == "numbers" ? "icon" : nil)
        // They pulse while tokens are being spent. Text only has no icon, Icon only no text.
        display.submenu?.addItem(.separator())
        display.submenu?.addItem(toggle(tr("loading_icon"), "loadingIcon", enabled: mode != "numbers"))
        display.submenu?.addItem(toggle(tr("loading_text"), "loadingText", enabled: mode != "icon"))
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
        let data = toggles(tr("data"), [(tr("fable"), "showFable"), (tr("pace_experimental"), "showPace"), (tr("budget"), "showBudget")])
        data.submenu?.addItem(.separator())
        for (value, name) in [("day", tr("budget_day")), ("hour", tr("budget_hour"))] {
            data.submenu?.addItem(choice(name, "speedColors", value, enabled: defaults.bool(forKey: "showBudget")))
        }
        data.submenu?.addItem(.separator())
        data.submenu?.addItem(toggle(tr("resets_in"), "showResets"))
        let head = [toggle(tr("profile_name"), "showProfile"), .separator(),
                    choice(tr("multiple_users"), "users", "multiple"), choice(tr("single_user"), "users", "single"), .separator()]
        for (index, entry) in head.enumerated() { data.submenu?.insertItem(entry, at: index) }
        // Hours a day spent using Claude, so the pace ignores the rest of the day.
        submenu(tr("work"), [("workHours", [24, 16, 12, 8, 6, 4].map { ($0, plural("hours", $0)) })])
        toggles(tr("notify"), [(tr("notify_reached"), NoticeKind.reached.setting), (tr("notify_reset"), NoticeKind.reset.setting),
                               (tr("notify_marks"), NoticeKind.week.setting)])
        // The globe is the website's language picker. Each language is named in itself, so it can always be found.
        let languages = NSMenu()
        for language in Language.allCases {
            let entry = NSMenuItem(title: "\(language.flag) \(language.name)", action: #selector(chooseLanguage), keyEquivalent: "")
            entry.target = self
            entry.representedObject = language.rawValue
            entry.state = language == .current ? .on : .off
            languages.addItem(entry)
        }
        let languageEntry = NSMenuItem(title: tr("language"), action: nil, keyEquivalent: "")
        languageEntry.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        languageEntry.submenu = languages
        menu.addItem(languageEntry)
        menu.addItem(.separator())
        // Registering from anywhere else (a build folder in /tmp) would point the login item at a bundle that disappears.
        action(tr("login"), #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled,
               enabled: Bundle.main.bundlePath.hasPrefix("/Applications/"))
        action(tr("dock"), #selector(toggleDock), on: inDock())
        menu.addItem(.separator())
        action(tr("about"), #selector(showAbout)).image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(.separator())
        // While an update installs, and until Reopen, its step stands in, in plain text that greys out:
        // the bold "Update available!" still looked clickable.
        let check = action(UpdateProgress.underway ?? tr("check"), #selector(checkNow), enabled: !checking && UpdateProgress.underway == nil)
        if let version = availableUpdate, UpdateProgress.underway == nil {
            check.attributedTitle = updateAvailableTitle(version)
            check.image = updateAvailableIcon()
        } else {
            check.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        }
        // A blank image lines the title up with the icon rows.
        submenu(tr("auto"), [("updateEvery", [(86400, tr("daily")), (604800, tr("weekly")), (0, tr("never"))])]).image = NSImage(size: NSSize(width: 16, height: 16))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: tr("quit"), action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: nil)
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let pick = (sender.representedObject as? [String: Any])?.first else { return }
        let before = shown
        defaults.set(pick.value, forKey: pick.key)
        log.notice("\(pick.key, privacy: .public) = \(String(describing: pick.value), privacy: .public)")
        if pick.key == "interval" { reschedule() }
        if shown != before { profilesChanged() }
        render()
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        log.notice("\(key, privacy: .public) = \(self.defaults.bool(forKey: key), privacy: .public)")
        if key == "onlyWhileClaude" { reschedule() }
        render()
    }

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        defaults.set(code, forKey: "language")
        log.notice("language = \(code, privacy: .public)")
        aboutWindow?.close()  // it was built in the old language
        aboutWindow = nil
        render()
    }

    @objc func addProfile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = tr("choose_folder")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path == FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude").path ? "" : url.path
        if !allProfiles.contains(path) {
            defaults.set(Array(allProfiles.dropFirst()) + [path], forKey: "profiles")
            load(path)
        }
        defaults.set(path, forKey: "profile")
        profilesChanged()
    }

    // Only forgets it here: the folder and its login stay.
    @objc func removeProfile() {
        guard !profile.isEmpty, alert(tr("remove_question", ["name": profileName(profile)]), tr("remove_info"), tr("remove"), tr("cancel"))
        else { return }
        let path = profile
        defaults.set(allProfiles.dropFirst().filter { $0 != path }, forKey: "profiles")
        defaults.removeObject(forKey: historyKey(path))
        accounts[path] = nil
        defaults.removeObject(forKey: "profile")
        profilesChanged()
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
