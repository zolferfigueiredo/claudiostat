import ClaudioStatStrings
import Foundation

// Writes each language's Localizable.strings into the folder given (widget.sh: the widget's Resources), keyed by the
// English text. macOS reads Edit Widget's names (Account, Focus, Theme, Session...) from these, not from the widget.

func quoted(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let english = Strings.all[.en] ?? [:]
for language in Language.allCases where language != .en {
    let table = Strings.all[language] ?? [:]
    let lines = english.sorted { $0.key < $1.key }.compactMap { key, text in table[key].map { "\(quoted(text)) = \(quoted($0));" } }
    let lproj = folder.appending(path: "\(language.rawValue).lproj")
    try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(to: lproj.appending(path: "Localizable.strings"), atomically: true, encoding: .utf8)
}
