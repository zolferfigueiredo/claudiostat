import AppIntents
import ClaudioStatStrings
import WidgetKit

// What a widget shows, chosen per widget: right-click it, then Edit. macOS shows these names in the language of the
// Mac, from the Localizable.strings that WidgetStrings writes into the widget, keyed by the English text: each name
// here has to be one of the app's English strings (Sources/ClaudioStat/Strings/en.swift), or it stays in English.

enum LimitChoice: String, AppEnum {
    case session, week, fable

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Limit"
    static let caseDisplayRepresentations: [LimitChoice: DisplayRepresentation] = [
        .session: "Session", .week: "Week", .fable: "Fable",
    ]
}

/// The widget's colors: the desktop's light or dark, or always one of them.
enum ThemeChoice: String, AppEnum {
    case auto, dark, light

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static let caseDisplayRepresentations: [ThemeChoice: DisplayRepresentation] = [
        .auto: "Automatic", .dark: "Dark", .light: "Light",
    ]
}

/// Rings or bars: each is its own widget in the gallery, so you see both before adding one.
enum StyleChoice {
    case rings, bars
}

/// What a widget shows: rings or bars, session and week always, P and B as its kind says, and Fable by itself once
/// it's used. Each kind is its own widget in the gallery.
struct Kind {
    let style: StyleChoice
    let rates: Bool

    /// "usage" is the rings widget with everything.
    var id: String {
        "usage" + (style == .bars ? ".bars" : "") + (rates ? "" : ".norates")
    }

    var description: String {
        tr(rates ? "widget_all" : "widget_limits")
    }
}

/// One type per kind, since a widget is a type.
protocol KindSpec {
    static var kind: Kind { get }
}

enum RingsAll: KindSpec { static let kind = Kind(style: .rings, rates: true) }
enum RingsFable: KindSpec { static let kind = Kind(style: .rings, rates: false) }
enum BarsAll: KindSpec { static let kind = Kind(style: .bars, rates: true) }
enum BarsFable: KindSpec { static let kind = Kind(style: .bars, rates: false) }

/// One of the app's profiles, for a widget set to it.
struct AccountEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static func all() -> [AccountEntity] {
        storedAccounts().map { AccountEntity(id: $0.id, name: $0.label) }
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        AccountEntity.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] { AccountEntity.all() }

    /// A new widget shows the first profile rather than an empty choice.
    func defaultResult() async -> AccountEntity? { AccountEntity.all().first }
}

struct UsageConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage"
    static let description = IntentDescription("Choose what this widget shows.")

    /// None: the profile checked in the app's menu.
    @Parameter(title: "Account") var account: AccountEntity?
    /// The limit with the big number in the middle of the rings. Session and week always show.
    @Parameter(title: "Focus", default: .session) var main: LimitChoice?
    @Parameter(title: "Theme", default: .auto) var theme: ThemeChoice?

    init() {}

    init(account: AccountEntity?) {
        self.account = account
    }

    var focus: LimitChoice { main ?? .session }

    /// The stored account this widget shows.
    var stored: StoredAccount? {
        account.flatMap { chosen in storedAccounts().first { $0.id == chosen.id } } ?? currentAccount()
    }
}
