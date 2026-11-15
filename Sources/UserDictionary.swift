import Foundation

/// Words added by hand: letters (initials or full pinyin) and the word they
/// type. The list is iOS/Keyboard/UserWords.tsv, built into the keyboard.
enum UserDictionary {
    static func normalised(_ code: String) -> String {
        code.lowercased().filter { $0.isASCII && $0.isLetter }
    }

    private static let byCode: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "UserWords", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2 else { continue }
            let code = normalised(fields[0])
            guard !code.isEmpty, !fields[1].isEmpty else { continue }
            map[code, default: []].append(fields[1])
        }
        return map
    }()

    static func words(for letters: String) -> [String] { byCode[normalised(letters)] ?? [] }
}
