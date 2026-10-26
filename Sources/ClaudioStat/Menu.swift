import AppKit
import ClaudioStatStrings
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
        let now = Date.now
        @discardableResult
        func action(_ title: String, _ selector: Selector, key: String = "", on: Bool = false, enabled: Bool = true) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            entry.target = self
            entry.state = on ? .on : .off
            entry.isEnabled = enabled
            menu.addItem(entry)
            return entry
        }
        // The choices of one setting.
        func submenu(_ title: String, _ key: String, _ options: [(value: Any, title: String)]) -> NSMenuItem {
            let choices = NSMenu()
            choices.autoenablesItems = false
            for (value, name) in options {
                let entry = NSMenuItem(title: name, action: #selector(choose), keyEquivalent: "")
                entry.target = self
                entry.representedObject = [key: value]
                entry.state = "\(defaults.object(forKey: key) ?? "")" == "\(value)" ? .on : .off
                choices.addItem(entry)
            }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = choices
            menu.addItem(entry)
            return entry
        }

        action(tr("settings"), #selector(showSettings), key: ",").image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(.separator())
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
                if let fable = usage?.fable { limit(letter("F", "fable"), fable) }
                let hourly = rate.week.unit == 3600
                // The value, then its unit: "Pace 3% · an hour".
                let per = { (name: String, value: Double?) in "\(name) \(percent(value))" + (value == nil ? "" : " · " + tr(hourly ? "an_hour" : "a_day")) }
                info(per(letter("P", "pace"), rate.week.speed))
                var budget = per(letter("B", "budget"), rate.week.needed)
                if let week = usage?.week, let reset = week.resetsAt, rate.week.needed != nil {
                    let left = reset.timeIntervalSince(now)
                    // Hourly, the budget divides over working hours only, so show those rather than the wall-clock countdown.
                    let over = hourly ? tr("hours_short", ["n": Int((left * Double(defaults.integer(forKey: "workHours")) / 24 / 3600).rounded(.up))])
                                      : span(left)
                    budget += " · " + tr("left_over", ["left": max(0, 100 - week.percent), "time": over])
                }
                info(budget)
            }
            let details = defaults.bool(forKey: "showDetails"), layout = defaults.string(forKey: "detailsLayout")
            if shown.count == 1 {
                action(tr("show_data"), #selector(toggleSetting), on: details).representedObject = "showDetails"
                if details { readings(shown[0], into: menu) }
            } else {
                // Several accounts shown: Show usage details picks how, each under its name. Off is showDetails unchecked.
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
                        menu.addItem(.separator())
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
            if !paused, let blockedUntil = accounts[profile]?.blockedUntil {
                action(tr("next_try", ["time": time(blockedUntil)]), #selector(refreshNow), enabled: false)
            }

            action(tr("refresh"), #selector(refreshNow), key: "r", enabled: !paused && !busy)
        }
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
        submenu(tr("auto"), "updateEvery", [(86400, tr("daily")), (604800, tr("weekly")), (0, tr("never"))]).image = NSImage(size: NSSize(width: 16, height: 16))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: tr("quit"), action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: nil)
        quit.target = NSApp
        menu.addItem(quit)
        showImages(menu)
    }

    /// Settings picked in the menu or the Settings window.
    func pick(_ picks: [String: Any]) {
        let before = shown
        for (key, value) in picks {
            defaults.set(value, forKey: key)
            log.notice("\(key, privacy: .public) = \(String(describing: value), privacy: .public)")
        }
        if picks["interval"] != nil || picks["onlyWhileClaude"] != nil { reschedule() }
        if shown != before { profilesChanged() }
        render()
        shareWithWidget()
    }

    @objc func choose(_ sender: NSMenuItem) {
        if let picks = sender.representedObject as? [String: Any] { pick(picks) }
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String { pick([key: !defaults.bool(forKey: key)]) }
    }

    func chooseLanguage(_ language: Language) {
        defaults.set(language.rawValue, forKey: "language")
        log.notice("language = \(language.rawValue, privacy: .public)")
        renameTabs()
        render()
        shareWithWidget()
    }

    @objc func addProfile() { showSetup(nextProfile(after: allProfiles)) }

    /// Links the profile to another Claude Code folder you use, like ~/.claude-work. Its name and switch stay, and the
    /// folder keeps its login: the setup checks it, and signs in only when there is none. The readings start over, as
    /// the folder may hold another account.
    func linkFolder(_ path: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude").standardizedFileURL.path
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: path.isEmpty ? home : path)
        panel.message = tr("link_info")
        panel.prompt = tr("link")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        // ~/.claude is "" here. A folder another profile has stays with it.
        let folder = url.path == home ? "" : url.path
        guard folder != path, !allProfiles.contains(folder) else { return }
        func moved(_ list: [String]) -> [String] { list.map { $0 == path ? folder : $0 } }
        defaults.set(moved(allProfiles), forKey: "profileList")
        defaults.set(moved(defaults.stringArray(forKey: "shownProfiles") ?? []), forKey: "shownProfiles")
        var custom = defaults.dictionary(forKey: "customNames") ?? [:]
        custom[folder] = custom.removeValue(forKey: path)
        defaults.set(custom, forKey: "customNames")
        var names = defaults.dictionary(forKey: "names") ?? [:]
        names[path] = nil
        defaults.set(names, forKey: "names")
        defaults.removeObject(forKey: historyKey(path))
        accounts[path] = nil
        load(folder)
        log.notice("linked \(folderName(path), privacy: .public) to \(folderName(folder), privacy: .public)")
        profilesChanged()
        showSetup(folder)
    }

    @objc func reconnect() { showSetup(profile) }

    // Signs it out of Claude Code too, so no login is left behind. The folder stays.
    func removeProfile(_ path: String) {
        guard alert(tr("remove_question", ["name": profileName(path)]), tr("remove_info"), tr("remove"), tr("cancel")) else { return }
        if let logout = claude(["auth", "logout"], configDir: path.isEmpty ? nil : path) {
            Task {
                do { try await run(logout) } catch { log.error("sign out \(folderName(path), privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
        defaults.set(allProfiles.filter { $0 != path }, forKey: "profileList")
        defaults.removeObject(forKey: historyKey(path))
        for key in ["names", "customNames"] {
            var names = defaults.dictionary(forKey: key) ?? [:]
            names[path] = nil
            defaults.set(names, forKey: key)
        }
        accounts[path] = nil
        profilesChanged()
    }

    /// A name of your own, shown wherever its email was. Left empty, the email comes back.
    func renameProfile(_ path: String) {
        var custom = defaults.dictionary(forKey: "customNames") ?? [:]
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = custom[path] as? String ?? ""
        field.placeholderString = defaults.dictionary(forKey: "names")?[path] as? String ?? folderName(path)
        let alert = NSAlert()
        alert.messageText = tr("rename_question", ["name": profileName(path)])
        alert.informativeText = tr("rename_info")
        alert.addButton(withTitle: tr("rename"))
        alert.addButton(withTitle: tr("cancel"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        custom[path] = name.isEmpty ? nil : name
        pick(["customNames": custom])
    }

    // The restart blinks the screen and the menu bar, so it's asked first. Cancel changes nothing.
    @objc func toggleDock() {
        guard alert(tr("dock_restart_title"), tr("dock_restart_text"), tr("dock_restart"), tr("cancel")) else { return }
        toggleDockTile()
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

// macOS 27 hides menu item images unless an item asks to show its own (preferredImageVisibility = .visible, 1).
// Set by key, as the macOS 26 SDK has no such property.
func showImages(_ menu: NSMenu) {
    guard #available(macOS 27, *) else { return }
    for item in menu.items {
        if item.image != nil { item.setValue(1, forKey: "preferredImageVisibility") }
        if let submenu = item.submenu { showImages(submenu) }
    }
}
