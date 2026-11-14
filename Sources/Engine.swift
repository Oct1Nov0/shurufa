import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

struct Snapshot: Decodable, Equatable {
    var preedit = ""
    var commit = ""
    var candidates: [String] = []
    var candidateDetails: [IndexedCandidate] = []
    var highlighted = 0
    var page = 0
    var lastPage = true
    var input = ""
    var pageSize = 7
    var requiredCandidate: String? = nil
    var literalCandidate = false
    var confidentCandidates: [String] = []
    var candidateWeights: [String: Int] = [:]
    var japaneseCandidates: [String] = []
    /// Guesses for mistyped letters, shown in the accent colour.
    var correctedCandidates: [String] = []
    var compactJapanese: IndexedCandidate? = nil
    var preferredCompleteMixed: String? = nil
    /// The hiragana and katakana of a romaji reading, kept second and third in the row.
    var pinnedKana: [String] = []
    var compactIndices: [Int] {
        let japanese = Set(japaneseCandidates)
        let first = candidates.firstIndex { japanese.contains($0) }
        let chinese = candidates.indices.filter { !japanese.contains(candidates[$0]) }
        if let first, first == 0, candidates[first] == preferredCompleteMixed {
            return [first] + chinese
        }
        return chinese + (first.map { [$0] } ?? [])
    }
    var layoutCandidates: [String] { candidates.map { $0 + (japaneseCandidates.contains($0) ? "　" : "") } }
}

struct CandidateMetadata: Decodable, Equatable {
    var kind: UInt32
    var scoreKind: UInt32
    var score: Double
    var consumedBytes: Int
    var remainingOffsetBytes: Int
    var remainingInput: String
}

struct IndexedCandidate: Decodable, Equatable {
    var index: Int
    var text: String
    var backendIndex: Int? = nil
    var source: Int? = nil
    var metadata: CandidateMetadata? = nil
    var consumedBytes: Int? = nil
    var remainingInput: String? = nil
}

struct PhraseModule: Codable, Identifiable {
    var id: String
    var apiVersion: Int
    var name: String
    var trigger: String
    var phrases: [String]
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    static let testing = CommandLine.arguments.contains("--smoke-languages") || CommandLine.arguments.contains("--smoke")
    static let enginePreview = Bundle.main.bundleIdentifier == "app.meowpuut.EnginePreview"
    private let defaults = Preferences.testing ? UserDefaults(suiteName: "app.meowpuut.smoke")! : UserDefaults.standard
    @Published var simplified: Bool { didSet { defaults.set(simplified, forKey: "simplified") } }
    @Published var modulesEnabled: Bool { didSet { defaults.set(modulesEnabled, forKey: "modulesEnabled") } }
    @Published var rememberChoices: Bool { didSet { defaults.set(rememberChoices, forKey: "rememberChoices") } }
    @Published var candidateTone: CandidateTone { didSet { defaults.set(candidateTone.rawValue, forKey: "candidateTone") } }
    @Published var glassStrength: GlassStrength { didSet { defaults.set(glassStrength.rawValue, forKey: "glassStrength") } }
    @Published var candidatePalette: CandidatePalette { didSet { defaults.set(candidatePalette.rawValue, forKey: "candidatePalette") } }
    @Published var glassShape: GlassShape { didSet { defaults.set(glassShape.rawValue, forKey: "glassShape") } }
    var inputMode: InputMode {
        get { InputMode(rawValue: defaults.string(forKey: "inputMode") ?? "") ?? .pinyin }
        set { defaults.set(newValue.rawValue, forKey: "inputMode") }
    }
    var keyboardBackend: InputBackendKind {
        get { InputBackendKind(rawValue: defaults.string(forKey: "keyboardBackend") ?? "") ?? .meowpuut }
        set { defaults.set(newValue.rawValue, forKey: "keyboardBackend") }
    }
    @Published var modules: [PhraseModule] = []
    @Published var moduleError = ""
    @Published var pins: [String: String] { didSet { defaults.set(pins, forKey: "candidatePins") } }
    static let directory = testing
        ? FileManager.default.temporaryDirectory.appendingPathComponent("Meowpuut-Smoke-\(ProcessInfo.processInfo.processIdentifier)")
        : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(enginePreview ? "Meowpuut Engine Preview" : "Meowpuut")
    var moduleDirectory: URL { Self.directory.appendingPathComponent("Modules") }
    private init() {
        glassShape = GlassShape(rawValue: defaults.string(forKey: "glassShape") ?? "") ?? .capsule
        candidateTone = CandidateTone(rawValue: defaults.string(forKey: "candidateTone") ?? "") ?? .system
        glassStrength = GlassStrength(rawValue: defaults.string(forKey: "glassStrength") ?? "") ?? .balanced
        candidatePalette = .graphite
        simplified = defaults.object(forKey: "simplified") as? Bool ?? true
        modulesEnabled = defaults.object(forKey: "modulesEnabled") as? Bool ?? true
        rememberChoices = defaults.object(forKey: "rememberChoices") as? Bool ?? (Self.testing || !Self.enginePreview)
        pins = defaults.dictionary(forKey: "candidatePins") as? [String: String] ?? [:]
        reload()
    }
    #if os(iOS)
    /// There is no settings app in this build; the defaults above apply.
    func applySharedSettings() {}
    #endif
    func reload() {
        do {
            try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
            let example = moduleDirectory.appendingPathComponent("hello.json")
            if !FileManager.default.fileExists(atPath: example.path), let bundled = Bundle.main.url(forResource: "hello", withExtension: "json", subdirectory: "Modules") {
                try FileManager.default.copyItem(at: bundled, to: example)
            }
            modules = []
            moduleError = ""
            for file in try FileManager.default.contentsOfDirectory(at: moduleDirectory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
                do {
                    let data = try Data(contentsOf: file)
                    guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
                    let module = try JSONDecoder().decode(PhraseModule.self, from: data)
                    guard module.apiVersion == 1, !module.id.isEmpty, !module.name.isEmpty, module.trigger.hasPrefix("/"), module.trigger.count > 1, module.phrases.count <= 100, !module.phrases.isEmpty, module.phrases.allSatisfy({ !$0.isEmpty && $0.count <= 4096 }) else { throw CocoaError(.fileReadCorruptFile) }
                    guard !modules.contains(where: { $0.id == module.id }) else { throw CocoaError(.fileReadCorruptFile) }
                    modules.append(module)
                } catch { moduleError += "\(file.lastPathComponent)：\(error.localizedDescription)\n" }
            }
        } catch { moduleError = error.localizedDescription }
    }
}

final class Engine: ObservableObject {
    static let toggleEnglishKey: Int32 = 0x100001
    static let modulesKey: Int32 = 0x100000
    static let literalSlashKey: Int32 = 0x100002
    @Published private(set) var inputMode: InputMode = .zhuyin
    @Published private(set) var backendKind: InputBackendKind = .meowpuut
    var learningTail: (reading: String, text: String, time: TimeInterval)?
    func learn(_ selections: [(reading: String, text: String)]) {
        var records: [(reading: String, text: String)] = []
        for selection in selections {
            var reading = selection.reading
            let suffix = reading.hasPrefix("py:") ? snapshot.input.lowercased() : snapshot.input
            if !suffix.isEmpty && reading.hasSuffix(suffix) { reading = String(reading.dropLast(suffix.count)) }
            records.append((reading, selection.text))
            let isChinese = !selection.text.isEmpty && selection.text.unicodeScalars.allSatisfy { (0x3400...0x9fff).contains($0.value) }
            guard isChinese else { learningTail = nil; continue }
            let now = Date().timeIntervalSince1970
            let prefix = reading.hasPrefix("py:") ? String(reading.prefix(5)) : String(reading.prefix(2))
            if let previous = learningTail, now - previous.time < 20, previous.reading.hasPrefix(prefix), previous.text.count + selection.text.count <= 8 {
                records.append(("ctx|" + previous.text + "|" + reading, selection.text))
                records.append((previous.reading + reading.dropFirst(prefix.count), previous.text + selection.text))
            }
            learningTail = (reading, selection.text, now)
        }
        ChoiceMemory.shared.remember(records)
    }
    var backend: InputBackend?
    var isReady: Bool { backend != nil }
    @Published var snapshot = Snapshot()
    @Published var predictions: [String] = []
    private(set) var predictionContext = ""
    /// The emoji and kaomoji that lead `predictions`, and the word they are for.
    private(set) var predictionSymbols: Symbols.Found?
    @Published var english = false
    @Published var error = ""
    var moduleBuffer: String?
    var moduleEnglishMode: Bool?
    var candidateOrder: [Int] = []
    var pendingChoices: [(reading: String, text: String)] = []
    /// Where the next letter goes in the reading (`snapshot.input`); nil is the end.
    @Published var caret: Int?
    /// The words chosen one after another for the reading now open, and what
    /// they wrote: a reading finished in two or more choices is learnt whole.
    var compositionChoices: [(reading: String, text: String)] = []
    var compositionCommit = ""
    @Published var browsing = false
    @Published var phrasesOnly = false
    @Published var browseCount = 0
    var pool: [IndexedCandidate] = []
    let explorationLimit = 256
    func candidates() -> [IndexedCandidate] {
        backend?.candidates(limit: explorationLimit) ?? []
    }
    func browse(phrases: Bool) {
        guard isReady, moduleBuffer == nil, !snapshot.input.isEmpty else { return }
        if !browsing { pool = candidates() }
        browsing = true; phrasesOnly = phrases
        showBrowsePage(0)
    }
    func showBrowsePage(_ requestedPage: Int) {
        let items = phrasesOnly ? pool.filter {
            $0.text.count > 1 && (snapshot.literalCandidate || $0.text.lowercased() != snapshot.input.lowercased())
        } : pool
        browseCount = items.count
        let page = max(0, min(requestedPage, max(0, (items.count - 1) / 7)))
        let start = min(page * 7, items.count)
        let visible = Array(items.dropFirst(start).prefix(7))
        candidateOrder = visible.map(\.index)
        snapshot.candidates = visible.map(\.text)
        snapshot.candidateDetails = visible
        snapshot.page = page; snapshot.lastPage = start + 7 >= items.count; snapshot.highlighted = 0
    }
    func finishComposition() {
        if moduleBuffer != nil {
            let raw = moduleBuffer ?? ""; clear(); snapshot.commit = raw; return
        }
        if !snapshot.candidates.isEmpty {
            if snapshot.highlighted == snapshot.candidates.count, snapshot.compactJapanese != nil {
                chooseCompactJapanese()
            } else {
                choose(snapshot.highlighted)
            }
        }
        var committed = takeCommit()
        while !snapshot.preedit.isEmpty {
            let previous = snapshot.input
            backend?.commit(); refresh()
            committed += takeCommit()
            if snapshot.input == previous { break }
        }
        snapshot.commit = committed
    }
    /// The hiragana and katakana of the input when all of it reads as romaji (a あ, sushi すし, xa ぁ).
    private func oneKana() -> [String] {
        guard !english, inputMode == .pinyin || inputMode == .japanese else { return [] }
        let letters = snapshot.input.lowercased()
        guard !letters.isEmpty, letters.count <= 64, letters.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-" || $0 == "'") }) else { return [] }
        let hiragana = Romaji.reading(letters)
        let scalars = Array(hiragana.unicodeScalars)
        // Anything left as a letter means the input is not romaji.
        guard !scalars.isEmpty, scalars.allSatisfy({ (0x3041...0x3096).contains($0.value) || $0.value == 0x30fc }),
              scalars.contains(where: { $0.value != 0x30fc }) else { return [] }
        let katakana = hiragana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? hiragana
        return hiragana == katakana ? [hiragana] : [hiragana, katakana]
    }
    /// The first page as this user wants it. Every word starts with the rank the
    /// lexicon gives it; each time a word is picked for a reading its count for
    /// that reading goes up by one, and picked words lead the row, most picked
    /// first (the latest pick first among equals). The kana of a romaji reading
    /// then take the second and third places.
    private func personalise() {
        snapshot.pinnedKana = []
        guard snapshot.page == 0, !snapshot.input.isEmpty, moduleBuffer == nil, !english else { return }
        let key = pinKey
        let usage = ChoiceMemory.shared.usage(for: key)
        let kana = oneKana()
        guard !usage.isEmpty || !kana.isEmpty else { return }
        let pool = candidates()
        var visible = snapshot.candidateDetails
        let kanaSet = Set(kana)
        if !usage.isEmpty {
            let context = learningTail.flatMap { Date().timeIntervalSince1970 - $0.time < 20 ? $0.text : nil }
            let after = ChoiceMemory.shared.contextual(for: key, after: context)
            var seen = Set<String>()
            // Emoji and kaomoji cells (-7, -8, and -1 other than kana) keep their own places.
            let picked = pool.filter { item in
                guard usage[item.text] != nil else { return false }
                if let source = item.source, source == -7 || source == -8 || (source == -1 && !kanaSet.contains(item.text)) { return false }
                return seen.insert(item.text).inserted
            }.sorted { a, b in
                let ca = after.contains(a.text), cb = after.contains(b.text)
                if ca != cb { return ca }
                let ua = usage[a.text]!, ub = usage[b.text]!
                if ua.uses != ub.uses { return ua.uses > ub.uses }
                if ua.lastUsed != ub.lastUsed { return ua.lastUsed > ub.lastUsed }
                return a.index < b.index
            }
            if !picked.isEmpty {
                let texts = Set(picked.map(\.text))
                visible.removeAll { texts.contains($0.text) }
                visible.insert(contentsOf: picked, at: 0)
            }
        }
        var slot = 1
        var pinned: [String] = []
        for text in kana {
            guard let item = visible.first(where: { $0.text == text }) ?? pool.first(where: { $0.text == text }) else { continue }
            pinned.append(text)
            if visible.first?.text == text { continue }
            visible.removeAll { $0.text == text }
            visible.insert(item, at: min(slot, visible.count))
            slot += 1
        }
        let page = Array(visible.prefix(max(7, snapshot.candidates.count)))
        guard page.map(\.index) != candidateOrder || !pinned.isEmpty else { return }
        candidateOrder = page.map(\.index)
        snapshot.candidates = page.map(\.text)
        snapshot.candidateDetails = page
        snapshot.highlighted = 0
        snapshot.pinnedKana = pinned
    }
    var pinKey: String {
        let script = Preferences.shared.simplified ? "s:" : "t:"
        switch inputMode {
        case .zhuyin: return script + snapshot.input
        case .pinyin: return "py:" + script + snapshot.input.lowercased()
        case .japanese: return "ja:" + snapshot.input
        }
    }
    func candidateShortcut(_ index: Int) -> String {
        (inputMode == .pinyin || moduleBuffer == "`" ? "" : "⇧") + String(index + 1)
    }
    var modeLabel: String {
        if english { return "ABC" }
        if inputMode == .japanese { return "あ" }
        return (inputMode == .pinyin ? "拼 · " : "") + (Preferences.shared.simplified ? "简" : "繁")
    }
    func isPinned(_ text: String) -> Bool { !snapshot.input.isEmpty && Preferences.shared.pins[pinKey] == text }
    func pin(_ index: Int) {
        guard !snapshot.input.isEmpty, snapshot.candidates.indices.contains(index) else { return }
        let text = snapshot.candidates[index]
        var pins = Preferences.shared.pins
        if pins[pinKey] == text { pins.removeValue(forKey: pinKey) } else { pins[pinKey] = text }
        Preferences.shared.pins = pins
        refresh()
    }
    init(_ kind: InputBackendKind = .meowpuut, mode: InputMode = .zhuyin) { configure(kind, mode: mode) }
    /// Starts without a backend; `install` supplies one later. The iOS
    /// keyboard uses this to draw its keys before the lexicon is parsed.
    init(deferredMode mode: InputMode) { inputMode = mode }
    /// Lets go of the backend and shows `mode` until `install` supplies the
    /// next one. The iOS keyboard uses this when the mode was changed in the
    /// app: the old lexicon is released before the new one is parsed.
    func unload(for mode: InputMode) {
        clear(); learningTail = nil
        backend = nil
        inputMode = mode
    }
    func selectMode(_ mode: InputMode) { configure(Preferences.shared.keyboardBackend, mode: mode) }
    func selectBackend(_ kind: InputBackendKind) { configure(kind, mode: inputMode) }
    private func configure(_ requestedKind: InputBackendKind, mode: InputMode) {
        let kind = requestedKind
        guard backend == nil || kind != backendKind || mode != inputMode else { return }
        do {
            install(try Self.makeBackend(mode: mode), kind: kind, mode: mode)
        } catch {
            self.error = Self.loadFailedMessage
        }
    }
    static var loadFailedMessage: String {
        Preferences.shared.simplified ? "无法加载词库。" : "無法載入詞庫。"
    }
    /// Builds the backend for a mode. The lexicon is parsed here, the slow
    /// part of starting up, so this may run off the main thread. With `warm`
    /// it also types and clears a short reading, so the first real key does
    /// not pay for opening the word database.
    static func makeBackend(mode: InputMode, warm: Bool = false) throws -> InputBackend {
        let next: InputBackend
        #if os(macOS)
        next = mode == .japanese ? try JapaneseBackend() : try ChineseWithJapaneseBackend(mode: mode, literalSpaceAddsSpace: false, emojiCell: false)
        #else
        if mode == .japanese {
            let japanese = try JapaneseBackend()
            japanese.symbolCells = true
            next = japanese
        } else {
            next = try ChineseWithJapaneseBackend(mode: mode)
        }
        #endif
        if warm {
            for scalar in (mode == .zhuyin ? "su3" : "ni").unicodeScalars { _ = next.key(Int32(scalar.value), modifiers: 0) }
            _ = next.snapshot()
            _ = next.candidates(limit: 32)
            next.clear()
            _ = next.snapshot()
        }
        return next
    }
    /// Makes a backend from `makeBackend` the current one (main thread).
    func install(_ next: InputBackend, kind: InputBackendKind = .meowpuut, mode: InputMode) {
        clear(); learningTail = nil
        backend = next
        backendKind = kind
        inputMode = mode
        error = ""
        modeChanged()
    }
    func refresh() {
        guard moduleBuffer == nil, let backend else { return }
        let pendingCommit = snapshot.commit
        snapshot = backend.snapshot()
        let newCommit = snapshot.commit
        snapshot.commit = pendingCommit + newCommit
        if let at = caret, at >= snapshot.input.count || snapshot.preedit.isEmpty { caret = nil }
        if !newCommit.isEmpty { compositionCommit += newCommit }
        if snapshot.preedit.isEmpty {
            if !compositionCommit.isEmpty { learnPhrase() }
            compositionChoices = []; compositionCommit = ""
        }
        if !newCommit.isEmpty {
            if pendingChoices.isEmpty { learningTail = nil }
            learn(pendingChoices)
            pendingChoices = []
        } else if snapshot.preedit.isEmpty { pendingChoices = [] }
        browsing = false; pool = []
        candidateOrder = snapshot.candidates.indices.map { snapshot.page * snapshot.pageSize + $0 }
        if snapshot.candidateDetails.count != snapshot.candidates.count {
            snapshot.candidateDetails = zip(candidateOrder, snapshot.candidates).map {
                IndexedCandidate(index: $0.0, text: $0.1, backendIndex: $0.0, source: inputMode == .japanese ? 1 : nil)
            }
        }
        personalise()
        if snapshot.page == 0, inputMode == .pinyin,
           !snapshot.candidates.contains(where: { snapshot.japaneseCandidates.contains($0) && !snapshot.pinnedKana.contains($0) }) {
            snapshot.compactJapanese = backend.compactJapanese()
        } else {
            snapshot.compactJapanese = nil
        }
        if !newCommit.isEmpty && snapshot.preedit.isEmpty {
            updatePredictions(context: newCommit)
        } else if !snapshot.preedit.isEmpty && !predictions.isEmpty {
            predictions = []
        }
    }
    func updatePredictions(context: String) {
        let clean = String(context.suffix(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english, snapshot.preedit.isEmpty, let backend, !clean.isEmpty else {
            if !predictions.isEmpty { predictions = [] }
            predictionContext = ""; predictionSymbols = nil
            return
        }
        // One emoji of the word just typed comes first (生日快樂 🎂); a second emoji and one
        // kaomoji come after the third word that may follow, so the next words stay in reach.
        // After a single character (有, 上, typed one by one) nothing leads: 🈶 or 👆 in the
        // first cell would only push the next words away.
        predictionSymbols = Symbols.after(clean, japanese: inputMode == .japanese)
        let leading = clean.count > 1 ? 1 : 0
        var merged = predictionSymbols.map { Array($0.emoji.prefix(leading)) } ?? []
        let later = predictionSymbols.map { Array($0.emoji.dropFirst(leading).prefix(2 - leading) + $0.kaomoji.prefix(1)) } ?? []
        let lead = merged.count
        let limit = 8 + lead + later.count
        if inputMode != .japanese,
           clean.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value) }) {
            for item in ChoiceMemory.shared.contextualPredictions(after: clean, limit: 3) + backend.predict(context: clean, limit: 8)
            where !merged.contains(item) {
                merged.append(item)
            }
            for mark in ["，", "。", "？", "！"] where merged.count < limit && !merged.contains(mark) {
                merged.append(mark)
            }
        }
        merged.insert(contentsOf: later.filter { !merged.contains($0) }, at: min(merged.count, lead + 3))
        predictionContext = merged.isEmpty ? "" : clean
        let next = Array(merged.prefix(limit))
        if predictions != next { predictions = next }
    }
    /// Remembers a reading typed in pieces (huo de | ti tou | you | qing ying) as
    /// one phrase, for its full letters and, in pinyin, for its initials (hdttyqy).
    private func learnPhrase() {
        guard compositionChoices.count >= 2, Preferences.shared.rememberChoices else { return }
        let phrase = compositionChoices.map(\.text).joined()
        guard phrase == compositionCommit, (2...20).contains(phrase.count) else { return }
        let key = compositionChoices[0].reading
        var records = [(reading: key, text: phrase)]
        if key.hasPrefix("py:"), key.count > 5 {
            let script = String(key.dropFirst(3).prefix(2))
            if let short = Self.initials(of: String(key.dropFirst(5))) { records.append(("py:" + script + short, phrase)) }
        }
        ChoiceMemory.shared.remember(records)
    }
    /// The first letter of each pinyin syllable, or nil when the letters are not
    /// whole pinyin syllables.
    static func initials(of letters: String) -> String? {
        guard letters.count >= 4, letters.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return nil }
        let syllables = SyllableBreaks.pinyin(letters).split(separator: "\u{2006}")
        guard syllables.count >= 2, syllables.joined() == letters else { return nil }
        let short = syllables.compactMap(\.first).map(String.init).joined()
        return short == letters ? nil : short
    }
    /// Puts the caret before the letter at `index` of the reading (its length is the end).
    func setCaret(_ index: Int) {
        guard canEditReading else { return }
        let count = snapshot.input.count
        caret = index >= count ? nil : max(0, index)
    }
    func takeCommit() -> String { let text = snapshot.commit; snapshot.commit = ""; return text }
    /// A reading of letters is open and can be edited inside (pinyin, Japanese).
    var canEditReading: Bool {
        backend != nil && moduleBuffer == nil && !english && (inputMode == .pinyin || inputMode == .japanese)
            && !snapshot.input.isEmpty && !snapshot.preedit.isEmpty
    }
    func moveCaret(by offset: Int) {
        guard canEditReading else { return }
        let count = snapshot.input.count
        let at = max(0, min(count, (caret ?? count) + offset))
        caret = at >= count ? nil : at
    }
    /// Puts a letter at the caret. False when the caret is at the end (type as usual).
    func insertAtCaret(_ code: Int32) -> Bool {
        guard canEditReading, let at = caret, let scalar = UnicodeScalar(UInt32(code)) else { return false }
        var letters = Array(snapshot.input)
        let index = min(at, letters.count)
        letters.insert(Character(scalar), at: index)
        replaceReading(String(letters), caret: index + 1)
        return true
    }
    /// Deletes the letter before the caret. False when the caret is at the end.
    func deleteAtCaret() -> Bool {
        guard canEditReading, let at = caret else { return false }
        guard at > 0 else { return true }
        var letters = Array(snapshot.input)
        letters.remove(at: min(at, letters.count) - 1)
        replaceReading(String(letters), caret: at - 1)
        return true
    }
    private func replaceReading(_ input: String, caret at: Int) {
        guard let backend else { return }
        backend.replaceInput(input)
        refresh()
        caret = at >= snapshot.input.count ? nil : at
    }
    func clear() {
        moduleBuffer = nil
        if let previous = moduleEnglishMode { english = previous; moduleEnglishMode = nil }
        backend?.clear()
        if snapshot != Snapshot() { snapshot = Snapshot() }
        if !predictions.isEmpty { predictions = [] }
        predictionContext = ""; predictionSymbols = nil
        candidateOrder = []
        pendingChoices = []
        caret = nil
        compositionChoices = []; compositionCommit = ""
        browsing = false; pool = []
    }
    func modeChanged() {
        guard let backend else { return }
        backend.setSimplified(Preferences.shared.simplified)
        if moduleBuffer == nil { refresh() }
    }
}
