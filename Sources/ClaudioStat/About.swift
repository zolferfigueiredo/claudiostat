import AppKit
import SwiftUI

/// Built when About opens, and again after the language changes.
var aboutWindow: NSWindow?

func makeAboutWindow() -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
    window.styleMask = [.titled, .closable]
    window.title = tr("about")
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    // The hosting controller only sizes the window once shown, too late for center().
    window.setContentSize(window.contentView!.fittingSize)
    window.center()
    return window
}

extension AppDelegate {
    @objc func showAbout() {
        NSApp.activate()
        if aboutWindow == nil { aboutWindow = makeAboutWindow() }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 8)
            Text("ClaudioStat").font(.title2.bold())
            HStack(spacing: 4) {
                Text(tr("by"))
                Link("Zolfer Figueiredo", destination: URL(string: "https://zolfer.com/")!)
            }
            .font(.subheadline)
            .padding(.vertical, 6)
            Text(tr("version", ["version": appVersion]))
            Button(tr("check")) { delegate.checkNow() }
                .padding(.vertical, 12)
            Divider()
            Link(tr("website"), destination: URL(string: "https://claudiostat.zolfer.com/")!)
                .padding(.top, 12)
            Text(tr("liked"))
                .padding(.top, 6)
            Button(tr("coffee")) { NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/zolfer")!) }
                .padding(.top, 4)
        }
        .frame(minWidth: 232)
        .padding(24)
        .fixedSize()
    }
}
