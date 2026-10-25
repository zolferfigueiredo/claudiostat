// Copied from appclaudiostat's apps/mobile/targets/widget for the desktop widget: copy it again when it changes there.
// Changed here: no Live Activity, the desktop's sizes, and no Edit Widget choices.
import SwiftUI
import WidgetKit

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        UsageWidget<RingsAll>()
        UsageWidget<RingsFable>()
        UsageWidget<BarsAll>()
        UsageWidget<BarsFable>()
    }
}

// The timeline and views are the phone's (UsageView.swift). Each kind (rings or bars, with or without P and B; Fable
// by itself once used) is its own widget, so the gallery shows them all.
struct UsageWidget<Spec: KindSpec>: Widget {
    var body: some WidgetConfiguration {
        let kind = Spec.kind
        return StaticConfiguration(kind: kind.id, provider: AppChoices(base: Provider(kind: kind))) {
            UsageView(entry: $0)
        }
        .configurationDisplayName(kind.style == .bars ? Text("Bars") : Text("Rings"))
        .description(Text(kind.description))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The phone's timeline with the app's choices: the profile checked in the menu, the session in the middle. Edit
/// Widget's own choices need the App Intents metadata Xcode adds to the bundle, which a SwiftPM build doesn't make.
struct AppChoices: TimelineProvider {
    let base: Provider

    func placeholder(in context: Context) -> Entry { base.placeholder(in: context) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        Task { completion(await base.snapshot(for: UsageConfig(), in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task { completion(await base.timeline(for: UsageConfig(), in: context)) }
    }
}
