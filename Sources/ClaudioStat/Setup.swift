import AppKit
import SwiftUI

var setupWindow: NSWindow?

extension AppDelegate {
    /// Gets one profile's folder answering: Claude Code installed, signed in to a plan. It joins the list once it does.
    func showSetup(_ path: String) {
        NSApp.activate()
        // Opening it again mid sign-in must not cancel that sign-in.
        if let window = setupWindow, window.isVisible, (window.delegate as? Setup)?.path == path {
            return window.makeKeyAndOrderFront(nil)
        }
        setupWindow?.close()
        let setup = Setup(path: path, app: self)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(setup: setup)))
        window.styleMask = [.titled, .closable]
        window.title = "ClaudioStat"
        window.isReleasedWhenClosed = false
        window.delegate = setup
        setup.window = window
        setup.start()
        // The hosting controller only sizes the window once shown, too late for center().
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        setupWindow = window
    }

    func connected(_ path: String, _ result: UsageResult) {
        if !allProfiles.contains(path) { defaults.set(allProfiles + [path], forKey: "profileList") }
        defaults.set(path, forKey: "profile")
        log.notice("connected \(folderName(path), privacy: .public)")
        // Not profilesChanged(): it would ask Claude Code again right away.
        apply(result, to: path)
        watchSessions()
        render()
    }

    @discardableResult
    func refreshName(_ path: String) async -> String? {
        guard let email = await accountEmail(configDir: path.isEmpty ? nil : path) else { return nil }
        var names = defaults.dictionary(forKey: "names") ?? [:]
        names[path] = email
        defaults.set(names, forKey: "names")
        return email
    }
}

@Observable final class Setup: NSObject, NSWindowDelegate {
    enum Step { case checking, notFound, signIn, signingIn, noAnswer, done(String) }

    let path: String
    let app: AppDelegate
    var step = Step.checking
    var failure: String?
    var email: String?
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var login: Process?

    init(path: String, app: AppDelegate) {
        self.path = path
        self.app = app
    }

    var configDir: String? { path.isEmpty ? nil : path }

    // ~/.claude is your own Claude Code login, so it is only signed in again when it has none.
    // A new folder always signs in, so it holds the account picked in the browser.
    func start() {
        if claudePath() == nil { step = .notFound }
        else if path.isEmpty || app.allProfiles.contains(path) { check() }
        else { step = .signIn }
    }

    func check() {
        step = .checking
        Task {
            let result = await fetchUsage(configDir: configDir)
            switch result {
            case .ok(let usage):
                app.awaitingReopen = window?.isVisible == true
                app.connected(path, result)
                step = .done(barText(usage, showFable: app.defaults.bool(forKey: "showFable"), showBudget: false).string)
                // Back over the browser after signing in.
                if window?.isVisible == true { window?.orderFrontRegardless() }
                email = await app.refreshName(path)
                app.render()
            case .notFound: step = .notFound
            case .signedOut: step = .signIn
            case .failed: step = .noAnswer
            }
        }
    }

    func signIn() {
        guard login == nil else { return }
        guard let process = claude(["auth", "login"], configDir: configDir) else { step = .notFound; return }
        if let configDir { try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true) }
        let errors = Pipe()
        process.standardError = errors
        login = process
        failure = nil
        step = .signingIn
        Task {
            do {
                try await run(process)
                login = nil
                check()
            } catch {
                login = nil
                step = .signIn
                // "Login failed: …", or nothing after Cancel. One that never started leaves the pipe open, so only after an exit.
                guard error is UpdateError else { return }
                do { for try await line in errors.fileHandleForReading.bytes.lines { failure = line; break } } catch {}
            }
        }
    }

    func reopen() {
        do {
            try relaunchWhenQuit()
            NSApp.terminate(nil)
        } catch {
            window?.close()
        }
    }

    // Terminating a process that never launched raises an exception.
    func cancel() { if login?.isRunning == true { login?.terminate() } }

    // Closed without Reopen: the numbers show now.
    func windowWillClose(_ notification: Notification) {
        cancel()
        app.awaitingReopen = false
        app.render()
    }
}

struct SetupView: View {
    let setup: Setup

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 12) {
                switch setup.step {
                case .checking:
                    waiting(tr("updating"))
                case .notFound:
                    Text(tr("not_found"))
                    buttons {
                        Button(tr("try_again")) { setup.start() }
                        Button(tr("get_claude_code")) { NSWorkspace.shared.open(URL(string: "https://code.claude.com/")!) }
                            .keyboardShortcut(.defaultAction)
                    }
                case .signIn:
                    Text(tr("sign_in_info"))
                    if let failure = setup.failure { Text(failure).foregroundStyle(.red) }
                    buttons { Button(tr("sign_in")) { setup.signIn() }.keyboardShortcut(.defaultAction) }
                case .signingIn:
                    waiting(tr("signing_in"))
                    buttons { Button(tr("cancel")) { setup.cancel() }.keyboardShortcut(.cancelAction) }
                case .noAnswer:
                    Text(tr("no_answer"))
                    buttons { Button(tr("try_again")) { setup.check() }.keyboardShortcut(.defaultAction) }
                case .done(let bar):
                    Text(bar).font(.headline.monospacedDigit())
                    Text(tr("connected", ["name": setup.email ?? profileName(setup.path)]))
                    buttons { Button(tr("reopen")) { setup.reopen() }.keyboardShortcut(.defaultAction) }
                }
            }
            // A fixed width wraps the text; fixedSize() then makes the window follow each step's height.
            .frame(width: 300, alignment: .leading)
        }
        .padding(20)
        .fixedSize()
    }

    func waiting(_ text: String) -> some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(text)
        }
    }

    func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
    }
}
