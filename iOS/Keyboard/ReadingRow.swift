import SwiftUI
import UIKit

/// The line above the candidate bar: what is being typed and not yet chosen,
/// with the words already chosen for it in front, and the caret. A finger on
/// the line places the caret among the letters and drags it.
struct ReadingRow: View {
    @ObservedObject var ui: KeyboardUIState
    var onCaret: (Int) -> Void = { _ in }
    var onEnd: () -> Void = {}

    private static let inset: CGFloat = 14
    private var fontSize: CGFloat { (ui.readingHeight * 0.68).rounded() }

    /// Where the characters of `text` end, from the left of the row's text. When
    /// the text is wider than `width` its head is cut and an ellipsis leads:
    /// `first` is the first character shown, `lead` the ellipsis width.
    struct Layout { var first: Int; var lead: CGFloat; var edges: [CGFloat] }
    static func layout(_ text: String, size: CGFloat, width: CGFloat) -> Layout {
        let font = UIFont.systemFont(ofSize: size)
        let widths = text.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
        var first = 0, lead: CGFloat = 0
        var total = widths.reduce(0, +)
        if total > width {
            lead = ("…" as NSString).size(withAttributes: [.font: font]).width
            while first < widths.count, total + lead > width { total -= widths[first]; first += 1 }
        }
        var edges: [CGFloat] = [], x = lead
        for w in widths.dropFirst(first) { x += w; edges.append(x) }
        return Layout(first: first, lead: lead, edges: edges)
    }

    /// The character boundary nearest to `x`, as an index into the whole text.
    static func boundary(at x: CGFloat, in layout: Layout) -> Int {
        var best = layout.first, distance = abs(x - layout.lead)
        for (offset, edge) in layout.edges.enumerated() where abs(x - edge) < distance {
            distance = abs(x - edge); best = layout.first + offset + 1
        }
        return best
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 2 * Self.inset - 4)
            let characters = Array(ui.reading)
            let shown = Self.layout(ui.reading, size: fontSize, width: width)
            let at = max(0, min(ui.readingCaret ?? characters.count, characters.count))
            let caretX = at <= shown.first ? shown.lead : shown.edges[at - shown.first - 1]
            ZStack(alignment: .leading) {
                if !characters.isEmpty {
                    Text((shown.first > 0 ? "…" : "") + String(characters[shown.first...]))
                        .font(.system(size: fontSize))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundColor(CandidateInk.text(dark: ui.dark).opacity(0.88))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: fontSize * 1.15)
                        .offset(x: caretX - 1)
                }
            }
            .padding(.horizontal, Self.inset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard ui.readingEditable else { return }
                    // While a finger is on the line the letters are shown as typed.
                    let typed = Self.layout(ui.readingRaw, size: fontSize, width: width)
                    let index = Self.boundary(at: value.location.x - Self.inset, in: typed)
                    onCaret(index - ui.readingPrefixCount)
                }
                .onEnded { _ in onEnd() })
            .accessibilityLabel(ui.reading)
        }
    }
}
