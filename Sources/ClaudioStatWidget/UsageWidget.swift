import AppIntents
import ClaudioStatStrings
import SwiftUI
import WidgetKit

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        UsageWidget<RingsAll>()
        UsageWidget<RingsFable>()
        BarsWidget<BarsAll>()
        BarsWidget<BarsFable>()
    }
}

// The timeline and views are in UsageView.swift. Each kind (rings or bars, with or without P and B; Fable by itself
// once used) is its own widget, so the gallery shows them all; Edit Widget chooses the profile, focus and theme.
// Those choices need the App Intents file widget.sh adds to the bundle.
struct UsageWidget<Spec: KindSpec>: Widget {
    var body: some WidgetConfiguration {
        let kind = Spec.kind
        return AppIntentConfiguration(kind: kind.id, intent: UsageConfig.self, provider: Provider(kind: kind)) {
            UsageView(entry: $0)
        }
        .configurationDisplayName(tr("rings"))
        .description(kind.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The bars draw every limit alike, so their Edit Widget has no Focus.
struct BarsWidget<Spec: KindSpec>: Widget {
    var body: some WidgetConfiguration {
        let kind = Spec.kind
        return AppIntentConfiguration(kind: kind.id, intent: BarsConfig.self, provider: BarsProvider(base: Provider(kind: kind))) {
            UsageView(entry: $0)
        }
        .configurationDisplayName(tr("bars"))
        .description(kind.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BarsConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage"
    static let description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Account") var account: AccountEntity?
    @Parameter(title: "Theme", default: .auto) var theme: ThemeChoice?

    /// The same choices as the rings', for their timeline and views.
    var usage: UsageConfig {
        let config = UsageConfig(account: account)
        config.theme = theme
        return config
    }
}

struct BarsProvider: AppIntentTimelineProvider {
    let base: Provider

    func placeholder(in context: Context) -> Entry { base.placeholder(in: context) }

    func snapshot(for configuration: BarsConfig, in context: Context) async -> Entry {
        await base.snapshot(for: configuration.usage, in: context)
    }

    func timeline(for configuration: BarsConfig, in context: Context) async -> Timeline<Entry> {
        await base.timeline(for: configuration.usage, in: context)
    }
}
