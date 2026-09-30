import AppKit

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
// Launch argument `-updateSite http://localhost:8022/` tests against the website's run.sh.
let site = URL(string: UserDefaults.standard.string(forKey: "updateSite") ?? "https://claudiostat.zolfer.com/")!

/// The site names the DMG after the version, the same rule its deploy.sh uses.
func dmgURL(_ version: String) -> URL { site.appending(path: "ClaudioStat-\(version).dmg") }

/// The version the site offers, or nil when it can't be reached.
func latestVersion() async -> String? {
    let request = URLRequest(url: site.appending(path: "latest.json"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json["version"] as? String
}

nonisolated func isNewer(_ remote: String, than local: String) -> Bool {
    remote.compare(local, options: .numeric) == .orderedDescending
}

/// `every` 0 means never.
nonisolated func updateCheckIsDue(last: Date?, every: TimeInterval, now: Date) -> Bool {
    every > 0 && now.timeIntervalSince(last ?? .distantPast) >= every
}

nonisolated struct UpdateError: LocalizedError {
    let errorDescription: String?
}

/// Only builds signed by this team install. A valid signature alone would accept anyone's app.
let teamRequirement = #"=anchor apple generic and certificate leaf[subject.OU] = "497V6MCDS8""#

/// Opens this app again once this process has quit, so the old and new copies never run at once.
func relaunchWhenQuit() throws {
    // The PID and the app path go in as $0 and $1, never spliced into the script.
    _ = try Process.run(URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", #"while kill -0 "$0" 2>/dev/null; do sleep 0.2; done; open "$1""#,
                                    "\(getpid())", Bundle.main.bundlePath])
}

/// "Update available!" over "Install version 0.3.1 now", for the menu item that replaces Check for updates.
func updateAvailableTitle(_ version: String) -> NSAttributedString {
    let bold = NSFontManager.shared.convert(NSFont.menuFont(ofSize: 0), toHaveTrait: .boldFontMask)
    let title = NSMutableAttributedString(string: "Update available!\n", attributes: [.font: bold])
    title.append(NSAttributedString(string: "Install version \(version) now",
                                    attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                                                 .foregroundColor: NSColor.secondaryLabelColor]))
    return title
}

/// The filled download arrow in the accent color, so the item stands out.
func updateAvailableIcon() -> NSImage? {
    NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Update available")?
        .withSymbolConfiguration(.init(paletteColors: [.controlAccentColor]))
}

/// Replaces the running bundle with the one in the DMG for `version`. The caller relaunches.
/// URLSession downloads carry no quarantine flag, so the new copy opens without the Gatekeeper prompt.
func install(_ version: String) async throws {
    let files = FileManager.default
    let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Bundle.main.bundleURL, create: true)
    defer { try? files.removeItem(at: work) }

    let (download, response) = try await URLSession.shared.download(from: dmgURL(version))
    let dmg = work.appending(path: "update.dmg")
    try files.moveItem(at: download, to: dmg)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(errorDescription: "The download failed.") }

    let mount = work.appending(path: "mount")
    try files.createDirectory(at: mount, withIntermediateDirectories: true)
    try await run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path)
    let fresh = work.appending(path: "ClaudioStat.app")
    do {
        try await run("/usr/bin/ditto", mount.appending(path: "ClaudioStat.app").path, fresh.path)
    } catch {
        try? await run("/usr/bin/hdiutil", "detach", mount.path, "-force")
        throw error
    }
    try? await run("/usr/bin/hdiutil", "detach", mount.path, "-force")

    do {
        try await run("/usr/bin/codesign", "--verify", "--strict", "-R" + teamRequirement, fresh.path)
    } catch {
        throw UpdateError(errorDescription: "The download isn't signed by Zolfer Figueiredo.")
    }
    let info = Bundle(url: fresh)?.infoDictionary
    guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
          info?["CFBundleShortVersionString"] as? String == version else {
        throw UpdateError(errorDescription: "The download isn't ClaudioStat \(version).")
    }
    _ = try files.replaceItemAt(Bundle.main.bundleURL, withItemAt: fresh)
}

private nonisolated func run(_ tool: String, _ arguments: String...) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
        process.terminationHandler = { process in
            if process.terminationStatus == 0 { done.resume() }
            else { done.resume(throwing: UpdateError(errorDescription: "\((tool as NSString).lastPathComponent) failed (\(process.terminationStatus)).")) }
        }
        do { try process.run() } catch { done.resume(throwing: error) }
    }
}

extension AppDelegate {
    @objc func autoCheck() {
        let every = TimeInterval(defaults.integer(forKey: "updateEvery"))
        guard updateCheckIsDue(last: defaults.object(forKey: "lastUpdateCheck") as? Date, every: every, now: .now) else { return }
        checkForUpdates(quiet: true)
    }

    @objc func checkNow() { checkForUpdates(quiet: false) }

    /// The newer version a check found, while this one is still older.
    var availableUpdate: String? {
        defaults.string(forKey: "availableVersion").flatMap { isNewer($0, than: appVersion) ? $0 : nil }
    }

    /// Once, right after a self-update relaunched into this version.
    func showUpdateComplete() {
        guard let version = defaults.string(forKey: "updatedTo") else { return }
        defaults.removeObject(forKey: "updatedTo")
        guard version == appVersion else { return }
        alert("Update complete!", "You're now using ClaudioStat \(appVersion), the newest version available.", "OK")
    }

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
            defaults.set(latest, forKey: "availableVersion")
            log.notice("latest \(latest, privacy: .public), running \(appVersion, privacy: .public)")
            guard isNewer(latest, than: appVersion) else {
                if !quiet { alert("You're up to date!", "ClaudioStat \(appVersion) is currently the newest version available.", "OK") }
                return
            }
            guard alert("ClaudioStat \(latest) is available", "You have \(appVersion). Update now?", "Update Now", "Later") else { return }
            do {
                guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
                    throw UpdateError(errorDescription: "ClaudioStat updates itself only when it runs from the Applications folder.")
                }
                try await install(latest)
                defaults.set(latest, forKey: "updatedTo")
                try relaunchWhenQuit()
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
}
