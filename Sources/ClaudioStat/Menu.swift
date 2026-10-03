import AppKit
import ServiceManagement

extension AppDelegate {
    // Opening the app again (its Dock shortcut, Spotlight, Finder) shows the menu at the pointer, or the setup
    // while there is no profile. That also reaches it when the notch hides the menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if allProfiles.isEmpty { addProfile() } else { item.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
        return false
    }

    // Rebuilt on every open, so countdowns and the login item state are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        lookForClaudeCode()
        // choice() checks the stored value, which can still name a removed profile.
        defaults.set(profile, forKey: "profile")
        let now = Date.now, mode = defaults.string(forKey: "menuBar")
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

        if allProfiles.isEmpty {
            // Nothing to show or refresh yet, so the menu starts with the one thing to do.
            action(tr("add_profile"), #selector(addProfile)).image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: nil)
        } else {
            // One profile's lines, into this menu or an account's submenu.
            func readings(_ path: String, into target: NSMenu) {
                func info(_ text: String, _ color: NSColor? = nil) {
                    let line = NSMenuItem()
                    line.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: color ?? NSColor.labelColor])
                    line.isEnabled = false
                    target.addItem(line)
                }
                func limit(_ name: String, _ value: Limit?, _ rate: Rate? = nil) {
                    let color = rate?.pace.color
                    let used = "\(name) \(percent(value?.percent))"
                    info(value?.resetsAt.map { tr("resets", ["limit": used, "time": span($0.timeIntervalSince(now))]) } ?? used, color)
                    if let reason = rate?.reason { info(reason, color) }
                }
                let usage = accounts[path]?.usage
                if let alert = warning(usage) { info("⚠ \(alert)") }
                let rate = pacing(now, path)
                // Other languages' words needn't start with the bar's letter (W is "Semana"), so each line starts with it.
                let letter = { (letter: String, key: String) in Language.current == .en ? tr(key) : "\(letter) · \(tr(key))" }
                limit(letter("S", "session"), usage?.session, rate.session)
                limit(letter("W", "week"), usage?.week, rate.week)
                limit(letter("F", "fable"), usage?.fable)
                let hourly = rate.week.unit == 3600
                let speed = percent(rate.week.speed)
                info("\(letter("P", "pace")) · " + (rate.week.speed == nil ? speed : tr(hourly ? "rate_hour" : "rate_day", ["n": speed])))
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
            let details = defaults.bool(forKey: "showDetails"), layout = defaults.string(forKey: "detailsLayout")
            if shown.count == 1 {
                action(tr("show_data"), #selector(toggleSetting), on: details).representedObject = "showDetails"
                if details { readings(shown[0], into: menu) }
            } else {
                // Several accounts shown: Show data below picks how, each under its name. Off is showDetails unchecked.
                let ways = NSMenu()
                ways.autoenablesItems = false
                let options: [(title: String, picks: [String: Any], on: Bool)] = [
                    (tr("profile_per_block"), ["showDetails": true, "detailsLayout": "blocks"], details && layout == "blocks"),
                    (tr("profile_per_submenu"), ["showDetails": true, "detailsLayout": "submenus"], details && layout == "submenus"),
                    (tr("off"), ["showDetails": false], !details)]
                for (title, picks, on) in options {
                    let entry = NSMenuItem(title: title, action: #selector(choose), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = picks
                    entry.state = on ? .on : .off
                    ways.addItem(entry)
                }
                let entry = NSMenuItem(title: tr("show_data"), action: nil, keyEquivalent: "")
                entry.submenu = ways
                menu.addItem(entry)
            }
            if details, shown.count > 1 {
                for path in shown {
                    if layout == "submenus" {
                        let lines = NSMenu()
                        lines.autoenablesItems = false
                        readings(path, into: lines)
                        let entry = NSMenuItem(title: profileName(path), action: nil, keyEquivalent: "")
                        entry.submenu = lines
                        menu.addItem(entry)
                    } else {
                        menu.addItem(.sectionHeader(title: profileName(path)))
                        readings(path, into: menu)
                    }
                }
            }
            menu.addItem(.separator())

            let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
            let status: String
            var fix: Selector?  // a signed-out or missing Claude Code opens the setup
            if paused { status = updated.map { tr("paused_updated", ["time": time($0)]) } ?? tr("paused") }
            else if let problem { status = tr(problem); fix = #selector(reconnect) }
            else if let failedAt { status = tr("failed", ["time": time(failedAt)]) }
            else { status = updated.map { tr("updated", ["time": time($0)]) } ?? tr("updating") }
            let statusLine = NSMenuItem(title: status, action: fix, keyEquivalent: "")
            statusLine.target = self
            statusLine.isEnabled = fix != nil
            menu.addItem(statusLine)

            action(tr("refresh"), #selector(tick), key: "r", enabled: !paused && !busy)

            submenu(tr("every"), [("interval", [1, 3, 5, 10].map { ($0 * 60, plural("minutes", $0)) })])
            if claudeInstalled {
                action(tr("only"), #selector(toggleSetting), on: defaults.bool(forKey: "onlyWhileClaude")).representedObject = "onlyWhileClaude"
            }
            action(tr("status"), #selector(openStatus))
        }
        menu.addItem(.separator())

        // Each profile is a Claude Code folder with its own login. The checked one fills the bar and this menu.
        let profiles = submenu(tr("profile"), [("profile", allProfiles.map { ($0, profileName($0)) })])
        profiles.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
        let add = NSMenuItem(title: tr("add_profile"), action: #selector(addProfile), keyEquivalent: "")
        add.target = self
        let remove = NSMenuItem(title: tr("remove_profile"), action: #selector(removeProfile), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = !allProfiles.isEmpty
        for entry in allProfiles.isEmpty ? [add, remove] : [.separator(), add, remove] { profiles.submenu?.addItem(entry) }

        // "numbers" stays the stored value from before the label became Text only.
        let display = submenu(tr("display"), [("menuBar", [("both", tr("both")), ("icon", tr("icon_only")), ("numbers", tr("text_only"))]),
                                              ("icon", [("app", tr("app_icon")), ("star", tr("star_icon"))])],
                              disabled: mode == "numbers" ? "icon" : nil)
        display.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
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
        let data = toggles(tr("data"), [(tr("fable"), "showFable"), (tr("pace"), "showPace"), (tr("budget"), "showBudget")])
        data.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
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
            .image = NSImage(systemSymbolName: "briefcase", accessibilityDescription: nil)
        toggles(tr("notify"), [(tr("notify_reached"), NoticeKind.reached.setting), (tr("notify_reset"), NoticeKind.reset.setting),
                               (tr("notify_marks"), NoticeKind.week.setting)])
            .image = NSImage(systemSymbolName: "bell", accessibilityDescription: nil)
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
        guard let picks = sender.representedObject as? [String: Any] else { return }
        let before = shown
        for (key, value) in picks {
            defaults.set(value, forKey: key)
            log.notice("\(key, privacy: .public) = \(String(describing: value), privacy: .public)")
        }
        if picks["interval"] != nil { reschedule() }
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

    @objc func addProfile() { showSetup(nextProfile(after: allProfiles)) }

    @objc func reconnect() { showSetup(profile) }

    // Signs it out of Claude Code too, so no login is left behind. The folder stays.
    @objc func removeProfile() {
        guard !allProfiles.isEmpty, alert(tr("remove_question", ["name": profileName(profile)]), tr("remove_info"), tr("remove"), tr("cancel"))
        else { return }
        let path = profile
        if let logout = claude(["auth", "logout"], configDir: path.isEmpty ? nil : path) {
            Task {
                do { try await run(logout) } catch { log.error("sign out \(folderName(path), privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
        defaults.set(allProfiles.filter { $0 != path }, forKey: "profileList")
        defaults.removeObject(forKey: historyKey(path))
        var names = defaults.dictionary(forKey: "names") ?? [:]
        names[path] = nil
        defaults.set(names, forKey: "names")
        accounts[path] = nil
        defaults.removeObject(forKey: "profile")
        profilesChanged()
    }

    // The restart blinks the screen and the menu bar, so it's asked first. Cancel changes nothing.
    @objc func toggleDock() {
        guard alert(tr("dock_restart_title"), tr("dock_restart_text"), tr("dock_restart"), tr("cancel")) else { return }
        toggleDockTile()
    }

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
