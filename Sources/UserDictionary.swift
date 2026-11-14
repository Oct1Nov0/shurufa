import Foundation

/// Words the person adds in the app: letters (initials or full pinyin) and a
/// word. The app writes the list into the shared container; the keyboard reads it.
struct UserWord: Codable, Identifiable, Equatable {
    var id = UUID()
    var code: String
    var word: String
}

enum UserDictionary {
    static let group = "group.app.selfuse.zhjakeyboard"
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("UserDictionary.json")
    }
    /// The shared container can be reached from this process.
    static var available: Bool { file != nil }
    static let starters: [UserWord] = [
        UserWord(code: "gsw", word: "告诉我"), UserWord(code: "ssm", word: "是什么"),
        UserWord(code: "szm", word: "首字母"), UserWord(code: "qz", word: "权重"),
        UserWord(code: "yyz", word: "有一种"),
    ]

    static func load() -> [UserWord]? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([UserWord].self, from: data)
    }
    static func save(_ words: [UserWord]) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(words).write(to: file, options: .atomic)
    }
    static func normalised(_ code: String) -> String {
        code.lowercased().filter { $0.isASCII && $0.isLetter }
    }

    // The keyboard's copy, by letters; read when the keyboard appears.
    private static var byCode: [String: [String]] = [:]
    static func reload() {
        var map: [String: [String]] = [:]
        for entry in load() ?? [] {
            let code = normalised(entry.code)
            guard !code.isEmpty, !entry.word.isEmpty else { continue }
            map[code, default: []].append(entry.word)
        }
        byCode = map
    }
    static func words(for letters: String) -> [String] { byCode[normalised(letters)] ?? [] }
}
