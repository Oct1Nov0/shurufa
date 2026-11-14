import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// Whole-sentence kana-kanji conversion by AzooKeyKanaKanjiConverter (MIT) with
/// its default dictionary (Apache-2.0). No neural model, no learning, no
/// prediction: only candidates that convert all of the kana given. Called on
/// one thread at a time, like the session.
enum JapaneseSentences {
    private static let converter = KanaKanjiConverter.withDefaultDictionary()
    private static let options: ConvertRequestOptions = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JapaneseSentences", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ConvertRequestOptions(N_best: 8, requireJapanesePrediction: false, requireEnglishPrediction: false,
                                     keyboardLanguage: .ja_JP, learningType: .nothing,
                                     memoryDirectoryURL: directory, sharedContainerURL: directory,
                                     textReplacer: .empty, specialCandidateProviders: [], metadata: nil)
    }()
    /// The last request: one reading is asked for more than once per key.
    private static var last: (kana: String, texts: [String])?

    /// Conversions of the whole of `kana` (hiragana and ー only), best first.
    static func convert(_ kana: String, limit: Int) -> [String] {
        guard !kana.isEmpty, kana.count <= 60,
              kana.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) || $0.value == 0x30fc }) else { return [] }
        if let last, last.kana == kana { return Array(last.texts.prefix(limit)) }
        var text = ComposingText()
        text.insertAtCursorPosition(kana, inputStyle: .direct)
        let result = converter.requestCandidates(text, options: options)
        let length = kana.count
        var seen = Set<String>(), texts: [String] = []
        for candidate in result.mainResults where candidate.rubyCount == length && seen.insert(candidate.text).inserted {
            texts.append(candidate.text)
        }
        last = (kana, texts)
        return Array(texts.prefix(limit))
    }
}
