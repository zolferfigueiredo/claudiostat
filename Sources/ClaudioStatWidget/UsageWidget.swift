// Copied from appclaudiostat's apps/mobile/targets/widget for the desktop widget: copy it again when it changes there.
// Changed here: no Live Activity, and the desktop's sizes.
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
// by itself once used) is its own widget, so the gallery shows them all; Edit Widget chooses the profile and focus.
struct UsageWidget<Spec: KindSpec>: Widget {
    var body: some WidgetConfiguration {
        let kind = Spec.kind
        return AppIntentConfiguration(kind: kind.id, intent: UsageConfig.self, provider: Provider(kind: kind)) {
            UsageView(entry: $0)
        }
        .configurationDisplayName(kind.style == .bars ? Text("Bars") : Text("Rings"))
        .description(Text(kind.description))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
