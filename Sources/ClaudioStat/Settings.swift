import AppKit
import ClaudioStatStrings
import SwiftUI

/// Built when Settings or About first opens, then kept.
var settingsWindow: NSWindow?

func makeSettingsWindow() -> NSWindow {
    let tabs = NSTabViewController()
    tabs.tabStyle = .toolbar
    // The window takes each tab's height as it shows.
    func add(_ key: String, _ symbol: String, _ view: some View) {
        let page = NSHostingController(rootView: view.frame(width: 480))
        page.sizingOptions = .preferredContentSize
        page.title = tr(key)
        let item = NSTabViewItem(viewController: page)
        item.identifier = key
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        tabs.addTabViewItem(item)
    }
    add("general", "gearshape", GeneralSettings())
    add("menu_bar", "menubar.rectangle", MenuBarSettings())
    // Unchanged otherwise, so only a new language draws it again.
    add("about_tab", "info.circle", Redrawn { AboutView().id(Language.current) })
    let window = NSWindow(contentViewController: tabs)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    window.center()
    return window
}

extension AppDelegate {
    @objc func showSettings() { showTab("general") }

    @objc func showAbout() { showTab("about_tab") }

    func showTab(_ tab: String) {
        NSApp.activate()
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        if let tabs = settingsWindow?.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = tabs.tabView.indexOfTabViewItem(withIdentifier: tab)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The tabs were named in the old language. The window takes its title from a tab as it opens.
    func renameTabs() {
        guard let tabs = settingsWindow?.contentViewController as? NSTabViewController else { return }
        for item in tabs.tabViewItems {
            item.label = tr(item.identifier as? String ?? "")
            item.viewController?.title = item.label
        }
        settingsWindow?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
    }
}

/// A setting for a control, stored like a pick in the menu.
func setting<Value>(_ key: String) -> Binding<Value> {
    Binding(get: { delegate.defaults.object(forKey: key) as? Value ?? AppDelegate.settings[key] as! Value },
            set: { delegate.pick([key: $0]) })
}

/// AppKit's switch at System Settings' size. SwiftUI's, beside other views in a row, ignores VoiceOver's press.
struct Switch: NSViewRepresentable {
    let label: String
    @Binding var isOn: Bool

    func makeNSView(context: Context) -> NSSwitch {
        let view = NSSwitch()
        view.target = context.coordinator
        view.action = #selector(Coordinator.flip)
        return view
    }

    func updateNSView(_ view: NSSwitch, context: Context) {
        context.coordinator.isOn = $isOn
        view.controlSize = .mini
        view.state = isOn ? .on : .off
        view.isEnabled = context.environment.isEnabled
        view.setAccessibilityLabel(label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }

    final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func flip(_ sender: NSSwitch) { isOn.wrappedValue = sender.state == .on }
    }
}

/// Drawn again whenever a setting changes, here or in the menu, so it shows it in the language picked.
struct Redrawn<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var changes = 0

    var body: some View {
        let _ = changes
        content().onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in changes += 1 }
    }
}

struct GeneralSettings: View {
    var body: some View {
        Redrawn {
            Form {
                Section(tr("app")) {
                    // Each language is named in itself, so it can always be found.
                    Picker(tr("language"), selection: Binding(get: { Language.current }, set: { delegate.chooseLanguage($0) })) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.name)").tag($0) }
                    }
                    if delegate.claudeInstalled { Toggle(tr("only"), isOn: setting("onlyWhileClaude")) }
                    Picker(tr("every"), selection: setting("interval") as Binding<Int>) {
                        ForEach([60, 180, 300, 600], id: \.self) { Text(plural("minutes", $0 / 60)).tag($0) }
                    }
                }
                // Each profile is a Claude Code folder with its own login. The ones switched on fill the bar, one after another.
                Section(tr("profile")) {
                    let all = delegate.allProfiles, on = delegate.shown
                    // A row is drawn again only when its item changes, so the item holds the names it shows.
                    let rows = all.map { (path: $0, name: profileName($0),
                                          email: delegate.defaults.dictionary(forKey: "names")?[$0] as? String ?? folderName($0)) }
                    ForEach(rows, id: \.path) { path, name, email in
                        HStack {
                            // The bar always shows one, so the last one on stays on.
                            Switch(label: name, isOn: Binding(get: { on.contains(path) }, set: { isOn in
                                delegate.pick(["shownProfiles": all.filter { $0 == path ? isOn : on.contains($0) }])
                            }))
                            .disabled(on == [path])
                            Text(name == email ? email : "\(name) (\(email))")
                            Spacer()
                            // After the action, so the window redraws once the alert is gone.
                            Button(tr("rename"), systemImage: "pencil") { Task { delegate.renameProfile(path) } }
                            Button(tr("remove"), systemImage: "trash") { Task { delegate.removeProfile(path) } }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    Button(tr("add_profile")) { delegate.addProfile() }
                }
                Section(tr("notify")) {
                    Toggle(tr("notify_reached"), isOn: setting(NoticeKind.reached.setting))
                    Toggle(tr("notify_reset"), isOn: setting(NoticeKind.reset.setting))
                    Toggle(tr("notify_marks"), isOn: setting(NoticeKind.week.setting))
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct MenuBarSettings: View {
    let appIcon: NSImage = {
        let icon = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)  // the star's size
        return icon
    }()

    var body: some View {
        Redrawn {
            // Text only has no icon, Icon only no text.
            let mode = delegate.defaults.string(forKey: "menuBar")
            Form {
                Section(tr("view")) {
                    // "numbers" stays the stored value from before the label became Text only.
                    Picker(tr("display"), selection: setting("menuBar") as Binding<String>) {
                        Text(tr("both")).tag("both")
                        Text(tr("icon_only")).tag("icon")
                        Text(tr("text_only")).tag("numbers")
                    }
                    // Each choice with the icon it puts in the menu bar.
                    Picker(tr("icon"), selection: setting("icon") as Binding<String>) {
                        Label { Text(tr("app_icon")) } icon: { Image(nsImage: appIcon) }.tag("app")
                        Label { Text(tr("star_icon")) } icon: { Image(nsImage: star(nil)) }.tag("star")
                    }
                    .disabled(mode == "numbers")
                    // The text on two lines.
                    Toggle(tr("compact_text"), isOn: setting("compactText")).disabled(mode == "icon")
                    // A soft rounded background behind the icon and text.
                    Toggle(tr("background"), isOn: setting("background"))
                }
                // What the menu bar shows after S and W. speedColors is the unit of P and B, which W's color compares.
                Section(tr("data")) {
                    Toggle(tr("profile_name"), isOn: setting("showProfile"))
                    Toggle(tr("resets_in"), isOn: setting("showResets"))
                    Toggle(tr("pace"), isOn: setting("showPace"))
                    Toggle(tr("budget"), isOn: setting("showBudget"))
                    // The menu's Pace and Budget lines and W's color use it too, so it stays on with both hidden.
                    Picker(tr("pace_budget"), selection: setting("speedColors") as Binding<String>) {
                        Text(tr("budget_day")).tag("day")
                        Text(tr("budget_hour")).tag("hour")
                    }
                    // Hours a day spent using Claude, so the pace ignores the rest of the day.
                    Picker(tr("work"), selection: setting("workHours") as Binding<Int>) {
                        ForEach([24, 16, 12, 8, 6, 4], id: \.self) { Text(plural("hours", $0)).tag($0) }
                    }
                }
                // They pulse while tokens are being spent.
                Section(tr("loading")) {
                    Toggle(tr("loading_icon"), isOn: setting("loadingIcon")).disabled(mode == "numbers")
                    Toggle(tr("loading_text"), isOn: setting("loadingText")).disabled(mode == "icon")
                }
            }
            .formStyle(.grouped)
        }
    }
}
