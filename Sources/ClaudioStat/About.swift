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
        HStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("ClaudioStat").font(.title2.bold())
                HStack(spacing: 4) {
                    Text(tr("by"))
                    Link("Zolfer Figueiredo", destination: URL(string: "https://zolfer.com/")!)
                }
                Text(tr("version", ["version": appVersion]))
                Link(tr("website"), destination: URL(string: "https://claudiostat.zolfer.com/")!)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .fixedSize()
    }
}
