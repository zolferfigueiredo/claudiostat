import Foundation
import Testing
@testable import ClaudioStat

/// "minutes.one" and "minutes.few" are forms of "minutes".
private func base(_ key: String) -> String {
    let parts = key.split(separator: ".")
    return ["one", "few", "many", "other"].contains(String(parts.last ?? "")) ? parts.dropLast().joined(separator: ".") : key
}

private func placeholders(_ text: String) -> Set<String> {
    Set(text.matches(of: /\{[a-z]+\}/).map { String($0.output) })
}

@Test func everyLanguageHasEveryString() {
    let english = Set(Strings.en.keys.map(base))
    for language in Language.allCases {
        let keys = Set((Strings.all[language] ?? [:]).keys.map(base))
        #expect(keys == english, "\(language.rawValue): \(keys.symmetricDifference(english).sorted())")
    }
}

// A translation that drops or misspells {version} would show the braces, or lose the number.
@Test func everyTranslationKeepsItsPlaceholders() {
    for language in Language.allCases {
        for (key, text) in Strings.all[language] ?? [:] {
            let english = Strings.en[key] ?? Strings.en[base(key) + ".other"] ?? ""
            #expect(placeholders(text) == placeholders(english), "\(language.rawValue) \(key): \(text)")
        }
    }
}

@Test func pluralForms() {
    #expect(plural("minutes", 1, in: .en) == "1 minute" && plural("minutes", 3, in: .en) == "3 minutes")
    #expect(plural("minutes", 0, in: .fr) == "0 minute" && plural("minutes", 2, in: .fr) == "2 minutes")
    // Russian and Polish: 1, then 2 to 4, then the rest, by the last digits.
    #expect([1, 3, 5, 11, 21, 22].map { plural("minutes", $0, in: .ru) } == ["1 минута", "3 минуты", "5 минут", "11 минут", "21 минута", "22 минуты"])
    #expect([1, 3, 5, 12, 22].map { plural("minutes", $0, in: .pl) } == ["1 minutę", "3 minuty", "5 minut", "12 minut", "22 minuty"])
    // One form for every number.
    #expect(plural("minutes", 1, in: .ja) == "1 分" && plural("minutes", 5, in: .ja) == "5 分")
}

@Test func missingStringsFallBackToEnglishThenTheKey() {
    #expect(tr("login", in: .it) == "Apri all’accesso")
    #expect(tr("not_a_key", in: .it) == "not_a_key")
    #expect(tr("version", ["version": "1.2.3"], in: .de) == "Version 1.2.3")
}

@Test func everyLanguageHasANameAndAFlag() {
    #expect(Language.allCases.count == 12)
    #expect(Set(Language.allCases.map(\.name)).count == 12 && Set(Language.allCases.map(\.flag)).count == 12)
    #expect(Language.pt.flag == "🇧🇷")
}
