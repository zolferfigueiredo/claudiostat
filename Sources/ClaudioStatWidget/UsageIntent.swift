// Copied from appclaudiostat's apps/mobile/targets/_shared for the desktop widget: copy it again when it changes there.
import AppIntents
import WidgetKit

// What a widget or complication shows, chosen per widget: touch and hold it, then Edit Widget.

@available(iOS 17.0, watchOS 10.0, *)
enum LimitChoice: String, AppEnum {
    case session, week, fable

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Limit"
    static let caseDisplayRepresentations: [LimitChoice: DisplayRepresentation] = [
        .session: "Session", .week: "Week", .fable: "Fable",
    ]
}

/// Rings or bars: each is its own widget in the gallery, so you see both before adding one.
enum StyleChoice {
    case rings, bars
}

/// What a widget shows: rings or bars, session and week always, P and B as its kind says, and Fable by itself once
/// it's used. Each kind is its own widget in the gallery (4 of them, as on the watch and Android).
struct Kind {
    let style: StyleChoice
    let rates: Bool

    /// The ids widgets were added with keep working: "usage" is the rings widget with everything.
    var id: String {
        "usage" + (style == .bars ? ".bars" : "") + (rates ? "" : ".norates")
    }

    var description: LocalizedStringResource {
        rates ? "Session, week, Fable, pace and budget." : "Session, week and Fable."
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

/// One of the phone's Claude accounts, for a widget set to it.
@available(iOS 17.0, watchOS 10.0, *)
struct AccountEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static func all() -> [AccountEntity] {
        storedAccounts().enumerated().map { AccountEntity(id: $1.id, name: $1.label($0)) }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        AccountEntity.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] { AccountEntity.all() }
}

@available(iOS 17.0, watchOS 10.0, *)
struct UsageConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage"
    static let description = IntentDescription("Choose what this widget shows.")

    /// None: the account the app shows.
    @Parameter(title: "Account") var account: AccountEntity?
    /// The limit that leads (outer ring, big number); none: the app's focus. Session and week always show.
    @Parameter(title: "Focus") var main: LimitChoice?

    init() {}

    init(main: LimitChoice? = nil, account: AccountEntity? = nil) {
        self.main = main
        self.account = account
    }

    /// The limit that leads: this widget's, else the app's.
    func focus(_ settings: Settings) -> LimitChoice {
        main ?? ["w": .week, "f": .fable][settings.main] ?? .session
    }

    /// The stored account this widget shows.
    var stored: StoredAccount? {
        account.flatMap { chosen in storedAccounts().first { $0.id == chosen.id } } ?? currentAccount()
    }

    /// The app's own choices (Settings), for the watch app's screen.
    init(_ settings: Settings) {
        main = ["w": .week, "f": .fable][settings.main] ?? .session
    }
}
