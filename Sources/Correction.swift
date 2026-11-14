import Foundation

/// Guesses at what was meant when the letters are not pinyin: one key hit next
/// to the right one, one letter left out, or one letter too many. Only spellings
/// made of whole pinyin syllables are kept, and only those the word list knows.
enum Correction {
    /// Keys around each key on the letter layout, beside it and above or below it.
    static let neighbours: [Character: [Character]] = {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(Array.init)
        let shift: [Double] = [0, 0.5, 1.5]   // where each row starts, in key widths
        var places: [(Character, Int, Double)] = []
        for (row, keys) in rows.enumerated() {
            for (index, key) in keys.enumerated() { places.append((key, row, Double(index) + shift[row])) }
        }
        var result: [Character: [Character]] = [:]
        for (key, row, x) in places {
            result[key] = places.filter { other in
                other.0 != key && ((other.1 == row && abs(other.2 - x) == 1) || (abs(other.1 - row) == 1 && abs(other.2 - x) <= 0.5))
            }.map(\.0)
        }
        return result
    }()
    /// Letters most often left out of a syllable: zh ch sh, ng, the i and u of a final.
    private static let dropped: [Character] = Array("hgiunaoe")

    /// Spellings one change away from `letters`.
    static func variants(of letters: String) -> [String] {
        let chars = Array(letters)
        var out: [String] = []
        var seen = Set<String>([letters])
        func add(_ c: [Character]) { let s = String(c); if seen.insert(s).inserted { out.append(s) } }
        for i in chars.indices {
            for near in neighbours[chars[i]] ?? [] { var c = chars; c[i] = near; add(c) }
        }
        for i in 0...chars.count {
            for letter in dropped { var c = chars; c.insert(letter, at: i); add(c) }
        }
        for i in chars.indices {
            // nn is not a slip: it is ん in romaji.
            if chars[i] == "n", (i > 0 && chars[i - 1] == "n") || (i + 1 < chars.count && chars[i + 1] == "n") { continue }
            var c = chars; c.remove(at: i); add(c)
        }
        return out
    }

    /// The best words for the likeliest spellings, best first.
    static func words(for letters: String, simplified: Bool, limit: Int = 3) -> [String] {
        guard (2...16).contains(letters.count), letters.allSatisfy({ $0.isASCII && $0.isLowercase }),
              letters.contains(where: { "aeiouv".contains($0) }),
              !SyllableBreaks.isWholePinyin(letters) else { return [] }
        var scored: [String: Int] = [:]
        var checked = 0
        for spelling in variants(of: letters) where SyllableBreaks.isWholePinyin(spelling) {
            checked += 1
            if checked > 40 { break }
            for (word, weight) in WordEvidence.shared.dictionary(input: spelling, mode: .pinyin, simplified: simplified)
            where word.count >= 2 || spelling.count <= 3 {
                scored[word] = max(scored[word] ?? 0, weight)
            }
        }
        return scored.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }
}
