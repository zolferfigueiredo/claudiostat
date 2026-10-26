import AppKit
import ClaudioStatStrings
import SwiftUI

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
