import SwiftUI
import UIKit

/// Layout and appearance the controller computes; the SwiftUI side only reads it.
final class KeyboardUIState: ObservableObject {
    @Published var region = CandidateRegionLayout(width: 393, idiom: .phone)
    @Published var keysAreaHeight: CGFloat = 213
    /// Space kept clear on the left and right (the safe area of a landscape phone).
    @Published var sideInset: CGFloat = 0
    @Published var trailingInset: CGFloat = 0
    @Published var expanded = false
    @Published var dark = false
    /// False while the keyboard is off screen.
    @Published var active = true
    /// English: completions and a correction for the word before the caret.
    @Published var suggestions: [String] = []
    /// Bumped when the extension reappears to rebuild the decorative layer.
    @Published var appearanceRevision = 0
    /// The kaomoji in the candidate row while the ^_^ list is open; empty when
    /// it is closed. Set when the list opens, so cells stay put while it is used.
    @Published var kaomojiRow: [String] = []
    var kaomojiOpen: Bool { !kaomojiRow.isEmpty }
    /// The clipboard holds text and the keyboard may read it (Full Access).
    @Published var canPaste = false
}

/// What the candidate area can ask the controller to do.
struct KeyboardActions {
    var chooseVisible: (Int) -> Void = { _ in }
    var choosePool: (IndexedCandidate) -> Void = { _ in }
    var selectPrediction: (Int) -> Void = { _ in }
    var insertSymbol: (String) -> Void = { _ in }
    var insertKaomoji: (String) -> Void = { _ in }
    var toggleExpanded: () -> Void = {}
    var dismiss: () -> Void = {}
    var paste: () -> Void = {}
    var switchScript: () -> Bool = { false }
    var delete: (Bool) -> Void = { _ in }
    var pool: () -> [IndexedCandidate] = { [] }
}

/// Candidates answer the finger at once with a soft capsule.
struct CandidatePressStyle: ButtonStyle {
    var tint: Color
    var dark: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule().fill(tint.opacity(dark ? 0.26 : 0.18))
                    .padding(.vertical, 6)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: configuration.isPressed)
    }
}

struct StripItem: Identifiable, Equatable {
    enum Target: Equatable { case visible(Int), pool(IndexedCandidate), prediction(Int), kaomoji(String) }
    var id: String
    var text: String
    var japanese: Bool
    var selected: Bool
    var width: CGFloat
    var target: Target
}

struct CandidateCell: View {
    let item: StripItem
    let fontSize: CGFloat
    let pillHeight: CGFloat
    let dark: Bool
    let palette: CandidatePalette
    var highContrast = false

    private var kaomoji: Bool { Kaomoji.contains(item.text) }

    var body: some View {
        HStack(spacing: 3) {
            Text(item.text)
                .font(.system(size: fontSize, weight: item.selected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            if item.japanese {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: (fontSize * 0.45).rounded()))
                    .rotationEffect(.degrees(-20))
                    .opacity(item.selected ? 0.9 : 0.6)
            }
        }
        .foregroundStyle(item.selected ? Color.white : CandidateInk.text(dark: dark))
        .padding(.horizontal, CandidateStripLayout.padding)
        // A kaomoji takes the width it is drawn at: its characters come from
        // fallback fonts, and the measured width can be short of that.
        .frame(minWidth: item.width, maxWidth: kaomoji ? nil : item.width, minHeight: pillHeight, maxHeight: pillHeight)
        .fixedSize(horizontal: kaomoji, vertical: false)
        .background {
            if item.selected { CandidatePill(palette: palette, dark: dark, highContrast: highContrast) }
        }
    }
}

struct CandidateRegionView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var ui: KeyboardUIState
    @ObservedObject var preferences = Preferences.shared
    let actions: KeyboardActions

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var extra: [IndexedCandidate] = []
    @State private var extraLoaded = false

    private var t: InterfaceText { InterfaceText(simplified: preferences.simplified) }
    private var dark: Bool { ui.dark }
    private var accent: Color { preferences.candidatePalette.color(dark: dark) }
    private var accessible: Bool { true }
    private var composing: Bool { !engine.snapshot.preedit.isEmpty }
    private var hasCandidates: Bool { !engine.snapshot.candidates.isEmpty || engine.snapshot.compactJapanese != nil }
    private var chineseActive: Bool { !engine.english && engine.inputMode != .japanese }

    var body: some View {
        let layout = ui.region
        let band = CandidateGlassShape.contentBand(preferences.glassShape, height: layout.glass.height)
        ZStack(alignment: .topLeading) {
            LiquidGlassBar(style: preferences.glassShape, dark: dark, accessible: accessible,
                           strength: preferences.glassStrength, tint: accent)
                .equatable()
                .frame(width: layout.glass.width, height: layout.glass.height)
                .position(x: layout.glass.midX, y: layout.glass.midY)
            rowContent(layout)
                .frame(width: layout.row.width, height: band.bottom - band.top)
                .position(x: layout.row.midX, y: layout.glass.minY + (band.top + band.bottom) / 2)
            chevron(layout)
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        // The rest of the pool belongs to one reading in one script.
        .onChange(of: engine.snapshot.input) { _, _ in resetExtra() }
        .onChange(of: preferences.simplified) { _, _ in resetExtra() }
    }

    private func resetExtra() {
        extra = []
        extraLoaded = false
    }

    // MARK: Row

    /// One unseen cell that keeps the strip's views built while it is idle.
    private static let placeholder = StripItem(id: "s0", text: "好", japanese: true, selected: true, width: 64,
                                               target: .visible(-1))

    private func rowContent(_ layout: CandidateRegionLayout) -> some View {
        let candidates = hasCandidates && !ui.expanded
        // The ^_^ list takes the row while nothing is being typed.
        let kaomoji = !candidates && !ui.expanded && !composing && ui.kaomojiOpen
        let words = engine.english ? ui.suggestions : engine.predictions
        let predictions = !candidates && !kaomoji && !ui.expanded && !composing && !words.isEmpty
        let showsStrip = candidates || kaomoji || predictions
        let list = candidates ? items(layout) : kaomoji ? kaomojiItems(layout)
            : predictions ? predictionItems(layout, words) : [Self.placeholder]
        return ZStack {
            // The strip stays in place, hidden, while there is nothing to
            // show: the first candidates then fill it in instead of building it.
            strip(layout, list: list)
                .opacity(showsStrip ? 1 : 0)
                .allowsHitTesting(showsStrip)
                .accessibilityHidden(!showsStrip)
            if ui.expanded {
                let title = composing ? engine.snapshot.preedit : t("顏文字", "颜文字")
                HStack {
                    Text(title)
                        .font(.system(size: layout.fontSize - 2, weight: .medium))
                        .foregroundStyle(CandidateInk.secondary(dark: dark))
                        .lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .accessibilityLabel(composing ? t("輸入中：", "输入中：") + title : title)
            } else if !showsStrip {
                idle(layout)
            }
        }
    }

    /// Words that may follow what was just typed, or in English the words
    /// the one being typed may become, in the same strip.
    private func predictionItems(_ layout: CandidateRegionLayout, _ words: [String]) -> [StripItem] {
        let size = layout.fontSize
        return words.enumerated().map { index, word in
            let width = CandidateStripLayout.cellWidth(text: CandidateTextMetrics.width(word, size: size), japanese: false,
                                                       paw: 0, maximum: layout.maximumCandidateWidth)
            return StripItem(id: "s\(index)", text: word, japanese: false, selected: false, width: max(44, width),
                             target: .prediction(index))
        }
    }

    /// The ^_^ list: recent kaomoji, then the first of every group.
    private func kaomojiItems(_ layout: CandidateRegionLayout) -> [StripItem] {
        ui.kaomojiRow.enumerated().map { index, text in
            let width = CandidateStripLayout.cellWidth(text: CandidateTextMetrics.width(text, size: layout.fontSize), japanese: false,
                                                       paw: 0, maximum: layout.maximumCandidateWidth)
            return StripItem(id: "s\(index)", text: text, japanese: false, selected: false, width: max(44, width),
                             target: .kaomoji(text))
        }
    }

    private func items(_ layout: CandidateRegionLayout) -> [StripItem] {
        let snapshot = engine.snapshot
        let size = layout.fontSize
        let paw = CandidateTextMetrics.paw(size: size)
        // The paw mark and the one-Japanese-candidate rule belong to Chinese
        // typing. In Japanese mode every candidate is Japanese: show them all.
        let japaneseTexts = engine.inputMode == .japanese ? [] : Set(snapshot.japaneseCandidates)
        var texts = snapshot.candidates
        var japanese = Set(texts.indices.filter { japaneseTexts.contains(texts[$0]) })
        if let compact = snapshot.compactJapanese {
            texts.append(compact.text)
            japanese.insert(texts.count - 1)
        }
        let pinned = snapshot.candidates.first.flatMap { $0 == snapshot.preferredCompleteMixed ? 0 : nil }
        // Only a Japanese word is moved up into view. The bare kana spelling
        // of the reading (source -1: にはお for nihao) keeps its ranked place
        // at the end of the row.
        let firstJapanese = texts.indices.first { japanese.contains($0) }
        let source = firstJapanese.flatMap { index in
            snapshot.candidateDetails.indices.contains(index) ? snapshot.candidateDetails[index].source : snapshot.compactJapanese?.source
        }
        let cells = CandidateStripLayout.cells(texts: texts, japanese: japanese, pinnedFirst: pinned,
                                               promoteJapanese: source != -1, keepAll: !snapshot.pinnedKana.isEmpty,
                                               available: layout.row.width, maximum: layout.maximumCandidateWidth,
                                               paw: paw) { CandidateTextMetrics.width($0, size: size) }
        // Cells are identified by their place in the row, so a keystroke
        // changes their text instead of replacing every cell.
        var result = cells.enumerated().map { slot, cell in
            StripItem(id: "s\(slot)", text: cell.text, japanese: cell.japanese,
                      selected: cell.index == snapshot.highlighted, width: cell.width, target: .visible(cell.index))
        }
        // Past the first page, like the system keyboard: the rest of the
        // ranked pool, without further Japanese readings.
        var seen = Set(texts)
        for candidate in extra where !seen.contains(candidate.text) && !japaneseTexts.contains(candidate.text) {
            seen.insert(candidate.text)
            let width = CandidateStripLayout.cellWidth(text: CandidateTextMetrics.width(candidate.text, size: size),
                                                       japanese: false, paw: paw, maximum: layout.maximumCandidateWidth)
            result.append(StripItem(id: "s\(result.count)", text: candidate.text, japanese: false,
                                    selected: false, width: width, target: .pool(candidate)))
        }
        return result
    }

    private func strip(_ layout: CandidateRegionLayout, list: [StripItem]) -> some View {
        let input = engine.snapshot.input
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CandidateStripLayout.spacing) {
                    ForEach(list) { item in
                        Button {
                            KeyboardFeedback.keyDown()
                            switch item.target {
                            case .visible(let index): actions.chooseVisible(index)
                            case .pool(let candidate): actions.choosePool(candidate)
                            case .prediction(let index): actions.selectPrediction(index)
                            case .kaomoji(let text): actions.insertKaomoji(text)
                            }
                        } label: {
                            CandidateCell(item: item, fontSize: layout.fontSize, pillHeight: layout.pillHeight,
                                          dark: dark, palette: preferences.candidatePalette,
                                          highContrast: contrast == .increased)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(CandidatePressStyle(tint: accent, dark: dark))
                        .accessibilityLabel(label(for: item))
                        .accessibilityAddTraits(item.selected ? .isSelected : [])
                        .id(item.id)
                    }
                    if !extraLoaded {
                        // A new marker for each reading, so it reports again
                        // when it is on screen for the next one.
                        Color.clear.frame(width: 1, height: 1)
                            .id("more|\(preferences.simplified)|" + input)
                            .onAppear { loadMore() }
                    }
                }
                .padding(.horizontal, 2)
            }
            .modifier(PlainScrollEdges())
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.94),
                                         .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            // A new reading, a new script or new predictions start from the left.
            .onChange(of: input) { _, _ in proxy.scrollTo("s0", anchor: .leading) }
            .onChange(of: preferences.simplified) { _, _ in proxy.scrollTo("s0", anchor: .leading) }
            .onChange(of: engine.predictions) { _, _ in proxy.scrollTo("s0", anchor: .leading) }
            .onChange(of: ui.suggestions) { _, _ in proxy.scrollTo("s0", anchor: .leading) }
            .onChange(of: ui.kaomojiRow) { _, _ in proxy.scrollTo("s0", anchor: .leading) }
        }
    }

    private func label(for item: StripItem) -> String {
        // A kaomoji is spoken as its group; its characters read as noise.
        if let kaomoji = Kaomoji.spokenName(item.text, simplified: preferences.simplified) { return kaomoji }
        if case .prediction = item.target { return (engine.english ? t("建議：", "建议：") : t("聯想詞：", "联想词：")) + item.text }
        return item.text + (item.japanese ? t("，日語", "，日语") : "")
    }

    private func loadMore() {
        guard !extraLoaded, composing else { return }
        extraLoaded = true
        let shown = Set(engine.candidateOrder + (engine.snapshot.compactJapanese.map { [$0.index] } ?? []))
        extra = actions.pool().filter { !shown.contains($0.index) }
    }

    private var idleStatus: String {
        if engine.english { return "English" }
        switch engine.inputMode {
        case .japanese: return "日本語"
        case .pinyin: return preferences.simplified ? "拼音 · 简体" : "拼音 · 繁體"
        case .zhuyin: return preferences.simplified ? "注音 · 简体" : "注音 · 繁體"
        }
    }

    /// The status where the row is short (a 320 pt keyboard).
    private var shortIdleStatus: String {
        guard chineseActive else { return idleStatus }
        return (engine.inputMode == .pinyin ? "拼 · " : "注 · ") + (preferences.simplified ? "简" : "繁")
    }

    private func markName(_ mark: String) -> String {
        switch mark {
        case "，": return t("逗號", "逗号")
        case "。": return t("句號", "句号")
        case "？": return t("問號", "问号")
        case "！": return t("驚嘆號", "感叹号")
        case "、": return t("頓號", "顿号")
        default: return mark
        }
    }

    /// Nothing is being typed and nothing is suggested: quick punctuation
    /// for Chinese, and what the keyboard is set to.
    private func idle(_ layout: CandidateRegionLayout) -> some View {
        let marks = chineseActive ? ["，", "。", "？", "！", "、"] : []
        let size = layout.statusFontSize
        // Text, its 0.5 pt tracking and the 6 pt after it.
        func width(_ text: String) -> CGFloat { CandidateTextMetrics.width(text, size: size) + 0.5 * CGFloat(text.count) + 8 }
        let fit = IdleRowLayout.fit(rowWidth: layout.row.width, marks: marks.count, markWidth: max(30, layout.fontSize * 1.55),
                                    fullStatus: width(idleStatus), shortStatus: width(shortIdleStatus))
        let status = fit.status == .full ? idleStatus : shortIdleStatus
        return HStack(spacing: 0) {
            if chineseActive {
                ForEach(marks, id: \.self) { mark in
                    Button {
                        KeyboardFeedback.keyDown()
                        actions.insertSymbol(mark)
                    } label: {
                        Text(mark)
                            .font(.system(size: layout.fontSize - 1, weight: .medium))
                            .foregroundStyle(CandidateInk.text(dark: dark).opacity(0.8))
                            .frame(width: fit.markWidth)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CandidatePressStyle(tint: accent, dark: dark))
                    // The mark's name alone: VoiceOver reads a bare mark as a pause.
                    .accessibilityLabel(markName(mark))
                }
            }
            Spacer(minLength: 0)
            if ui.canPaste {
                Button {
                    KeyboardFeedback.keyDown()
                    actions.paste()
                } label: {
                    Label(t("貼上", "粘贴"), systemImage: "doc.on.clipboard")
                        .font(.system(size: size, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(CandidateInk.text(dark: dark).opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CandidatePressStyle(tint: accent, dark: dark))
            } else if fit.status != .hidden {
                Text(status)
                    .font(.system(size: size, weight: .medium)).tracking(0.5)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(CandidateInk.secondary(dark: dark))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: status)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
                    .accessibilityLabel(t("目前輸入：", "当前输入：") + idleStatus)
            }
        }
    }

    /// The key at the right end: with candidates (or the kaomoji list) it opens
    /// and closes the panel; with nothing to show it puts the keyboard away.
    private func chevron(_ layout: CandidateRegionLayout) -> some View {
        let expands = hasCandidates || ui.kaomojiOpen || ui.expanded
        return Button {
            KeyboardFeedback.keyDown()
            if expands { actions.toggleExpanded() } else { actions.dismiss() }
        } label: {
            Image(systemName: expands ? "chevron.down" : "keyboard.chevron.compact.down")
                .font(.system(size: 15, weight: .semibold))
                .rotationEffect(.degrees(ui.expanded ? 180 : 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: ui.expanded)
                .foregroundStyle(CandidateInk.text(dark: dark).opacity(0.85))
                .frame(width: layout.chevron.width, height: layout.chevron.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: layout.chevron.midX, y: layout.chevron.midY)
        .accessibilityLabel(!expands ? t("收起鍵盤", "收起键盘")
                            : ui.kaomojiOpen && !composing ? (ui.expanded ? t("收合顏文字", "收起颜文字") : t("展開顏文字", "展开颜文字"))
                            : (ui.expanded ? t("收合候選詞", "收起候选词") : t("展開候選詞", "展开候选词")))
    }
}
