import AppKit
import Testing
@testable import ClaudioStat

// Settings the bar screenshots vary, and the ones that don't change the bar. A new setting has to go in one of them,
// and when it changes the bar, into the looks below too.
private let onTheBar: Set<String> = ["menuBar", "icon", "compactText", "showPace", "showBudget", "speedColors", "showResets",
                                     "showProfile", "users", "loadingIcon", "loadingText", "onlyWhileClaude"]
private let offTheBar: Set<String> = ["interval", "updateEvery", "notifyReached", "notifyReset", "notifyWeek", "showDetails",
                                      "detailsLayout", "workHours"]

@MainActor @Test func everySettingIsInTheScreenshots() {
    let placed = onTheBar.union(offTheBar), settings = Set(AppDelegate.settings.keys)
    #expect(settings == placed, "Place these in BarScreenshots.swift: \(settings.symmetricDifference(placed).sorted())")
}

/// Where screenshots.sh wants the pictures. Without it the test is skipped: it puts an item in the menu bar while it runs.
private let folder = ProcessInfo.processInfo.environment["SCREENSHOTS"]

/// A Monday noon, nudged to where the loading fade is faintest, so every run draws the same pictures.
private let now: Date = {
    let noon = ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z")!
    let phase = noon.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5)
    return noon.addingTimeInterval((0.75 - phase + 1.5).truncatingRemainder(dividingBy: 1.5))
}()
private let work = "/tmp/claudiostat-screenshots/.claude-work"

/// One profile's readings: S resets in 4h21, W and F in 6d8h. S rose `sessionRise` in the last half hour,
/// W `weekRise` in the last hour, which make the pace: the defaults are calm, S 8 is orange and 11 red, W 2 orange and 3 red.
@MainActor private func account(session: Int = 32, week: Int = 13, fable: Int = 7, sessionRise: Int = 2, weekRise: Int = 1,
                                _ edit: (inout Usage) -> Void = { _ in }) -> Account {
    func usage(_ session: Int, _ week: Int) -> Usage {
        Usage(session: Limit(percent: session, resetsAt: now.addingTimeInterval(15660)),
              week: Limit(percent: week, resetsAt: now.addingTimeInterval(547200)),
              fable: Limit(percent: fable, resetsAt: now.addingTimeInterval(547200)))
    }
    var latest = usage(session, week)
    edit(&latest)
    return Account(usage: latest, samples: [Sample(at: now.addingTimeInterval(-3600), usage: usage(session - 2 * sessionRise, week - weekRise)),
                                            Sample(at: now.addingTimeInterval(-1800), usage: usage(session - sessionRise, week - weekRise)),
                                            Sample(at: now, usage: latest)],
                   updated: now)
}

@MainActor private struct Look {
    var section: String
    var name: String
    var settings: [String: Any]
    var two = false
    var personal = account()
    var state: (AppDelegate) -> Void = { _ in }
}

@MainActor private func looks() -> [Look] {
    let displays = [("icon and text", "both"), ("text only", "numbers")]
    let icons = [("app icon", "app"), ("star", "star")]
    let letters: [(name: String, settings: [String: Any], fable: Int)] = [
        ("S W", [:], 0), ("S W F", [:], 7), ("S W F P B", ["showPace": true, "showBudget": true], 7),
        ("S W F P B per hour", ["showPace": true, "showBudget": true, "speedColors": "hour"], 7),
        ("S W B", ["showBudget": true], 0), ("S W P", ["showPace": true], 0)]
    let profiles: [(name: String, settings: [String: Any], two: Bool)] = [
        ("one profile", [:], false), ("one profile named", ["showProfile": true], false),
        ("two profiles", ["users": "multiple"], true), ("two profiles named", ["users": "multiple", "showProfile": true], true)]
    func name(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " · ") }
    var found: [Look] = []

    for (display, menuBar) in displays {
        for (iconName, icon) in menuBar == "numbers" ? [(nil, "app")] : icons.map({ (Optional($0.0), $0.1) }) {
            for compact in [true, false] {
                for letter in letters {
                    for resets in [false, true] {
                        for profile in profiles {
                            let settings = ["menuBar": menuBar, "icon": icon, "compactText": compact, "showResets": resets]
                                .merging(letter.settings) { $1 }.merging(profile.settings) { $1 }
                            found.append(Look(section: "Layouts", name: name(display, iconName, compact ? "compact" : "one line", letter.name,
                                                                             resets ? "resets" : nil, profile.name),
                                              settings: settings, two: profile.two, personal: account(fable: letter.fable)))
                        }
                    }
                }
            }
        }
    }
    for (iconName, icon) in icons {
        found.append(Look(section: "Layouts", name: name("icon only", iconName), settings: ["menuBar": "icon", "icon": icon]))
    }

    let thinking = { (app: AppDelegate) in app.midReply = ["transcript": now] }
    let states: [(name: String, personal: Account, settings: [String: Any], state: (AppDelegate) -> Void)] = [
        ("S orange", account(sessionRise: 8), [:], { _ in }),
        ("S red", account(sessionRise: 11), [:], { _ in }),
        ("W and P orange", account(weekRise: 2), [:], { _ in }),
        ("W and P red", account(weekRise: 3), [:], { _ in }),
        ("session reached", account { $0.session?.percent = 100; $0.session?.locked = true }, [:], { _ in }),
        ("week flagged", account { $0.week?.severity = "approaching_limit" }, [:], { _ in }),
        ("Fable reached", account { $0.fable?.percent = 100; $0.fable?.locked = true }, [:], { _ in }),
        ("rate limited", account(), [:], { $0.accounts[""]?.blockedUntil = now.addingTimeInterval(1200) }),
        ("paused", account(), ["onlyWhileClaude": true], { $0.claudeInstalled = true }),
        ("loading icon", account(), [:], thinking),
        ("loading text", account(), ["loadingIcon": false, "loadingText": true], thinking),
        ("loading icon and text", account(), ["loadingText": true], thinking),
        ("no profile", account(), [:], { _ in UserDefaults.standard.set([String](), forKey: "profileList") }),
        ("waiting for the first reading", Account(), [:], { _ in }),
        ("waiting for Reopen", account(), [:], { $0.awaitingReopen = true }),
    ]
    for state in states {
        var variants: [(name: String, settings: [String: Any], two: Bool)] = []
        for (display, menuBar) in displays {
            for (iconName, icon) in menuBar == "numbers" ? [(nil, "app")] : icons.map({ (Optional($0.0), $0.1) }) {
                for compact in [true, false] where icon == "app" || compact {
                    for (profile, two) in [("one profile", false), ("two profiles", true)] {
                        variants.append((name(display, iconName, compact ? "compact" : "one line", profile),
                                         ["menuBar": menuBar, "icon": icon, "compactText": compact, "users": two ? "multiple" : "single"], two))
                    }
                }
            }
        }
        for (iconName, icon) in icons { variants.append((name("icon only", iconName), ["menuBar": "icon", "icon": icon], false)) }
        for variant in variants {
            let settings = ["showPace": true, "showBudget": true, "showResets": true].merging(variant.settings) { $1 }
                .merging(state.settings) { $1 }
            found.append(Look(section: "States", name: name(state.name, variant.name), settings: settings, two: variant.two,
                              personal: state.personal, state: state.state))
        }
    }

    for language in Language.allCases {
        for compact in [true, false] {
            found.append(Look(section: "Languages", name: name(language.rawValue, language.name, compact ? "compact" : "one line"),
                              settings: ["language": language.rawValue, "compactText": compact, "showPace": true, "showBudget": true,
                                         "showResets": true]))
        }
    }
    return found
}

/// The status item's button as drawn on a dark menu bar and a light one, side by side, at 2x.
/// Drawn from a plain button with the same icon and text: a status bar button draws no text outside the menu bar.
@MainActor private func picture(_ item: NSStatusBarButton) -> Data {
    let button = NSButton()
    button.isBordered = false
    button.image = item.image
    button.attributedTitle = item.attributedTitle
    button.imagePosition = item.imagePosition
    button.isEnabled = !item.appearsDisabled
    let size = NSSize(width: ceil(button.intrinsicContentSize.width), height: NSStatusBar.system.thickness)
    button.setFrameSize(size)
    let pad: CGFloat = 8, panel = NSSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
    func bitmap(_ size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        // A new bitmap's memory isn't cleared.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.set()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    let sheet = bitmap(NSSize(width: 2 * panel.width, height: panel.height))
    for (index, (appearance, white)) in [(NSAppearance.Name.darkAqua, 0.16), (.aqua, 0.93)].enumerated() {
        button.appearance = NSAppearance(named: appearance)
        let shot = bitmap(size)
        button.cacheDisplay(in: NSRect(origin: .zero, size: size), to: shot)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        let origin = NSPoint(x: CGFloat(index) * panel.width, y: 0)
        NSColor(white: white, alpha: 1).setFill()
        NSRect(origin: origin, size: panel).fill()
        shot.draw(in: NSRect(origin: NSPoint(x: origin.x + pad, y: pad), size: size), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    return sheet.representation(using: .png, properties: [:])!
}

@MainActor @Test(.enabled(if: folder != nil)) func barScreenshots() throws {
    let out = URL(fileURLWithPath: folder!), defaults = UserDefaults.standard
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    _ = NSApplication.shared
    NSApp.applicationIconImage = NSImage(contentsOf: root.appending(path: "Icon/icon.png"))
    defaults.register(defaults: AppDelegate.settings)
    let app = AppDelegate()
    defer { NSStatusBar.system.removeStatusItem(app.item) }

    var gallery = "# ClaudioStat bar looks\n\nEvery look of the menu bar, dark on the left and light on the right. Made by `screenshots.sh`.\n"
    var section = ""
    for look in looks() {
        for key in Array(AppDelegate.settings.keys) + ["profile", "profileList", "names", "language"] { defaults.removeObject(forKey: key) }
        defaults.set("en", forKey: "language")
        defaults.set(look.two ? ["", work] : [""], forKey: "profileList")
        defaults.set(["": "personal", work: "work"], forKey: "names")
        for (key, value) in look.settings { defaults.set(value, forKey: key) }
        app.accounts = ["": look.personal, work: account(session: 64, week: 41, fable: 0, sessionRise: 3, weekRise: 0)]
        app.awaitingReopen = false
        app.midReply = [:]
        app.claudeInstalled = false
        look.state(app)
        app.render(at: now)

        let file = look.name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-") + ".png"
        #expect(!FileManager.default.fileExists(atPath: out.appending(path: file).path), "two looks named \(file)")
        try picture(app.item.button!).write(to: out.appending(path: file))
        if look.section != section {
            section = look.section
            gallery += "\n## \(section)\n\n| Look | Bar |\n|---|---|\n"
        }
        gallery += "| \(look.name) | ![\(look.name)](\(file)) |\n"
    }
    app.pulse?.invalidate()
    try gallery.write(to: out.appending(path: "README.md"), atomically: true, encoding: .utf8)
}
