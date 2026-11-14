import SwiftUI

/// The line above the candidate bar: what is being typed and not yet chosen,
/// with the words already chosen for it in front, and the caret.
struct ReadingRow: View {
    @ObservedObject var ui: KeyboardUIState

    var body: some View {
        HStack(spacing: 0) {
            if !ui.reading.isEmpty {
                let characters = Array(ui.reading)
                let at = max(0, min(ui.readingCaret ?? characters.count, characters.count))
                (Text(String(characters[..<at]))
                    + Text("|").foregroundColor(.accentColor).fontWeight(.semibold)
                    + Text(String(characters[at...])))
                    .font(.system(size: ui.readingHeight * 0.68))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(CandidateInk.text(dark: ui.dark).opacity(0.88))
                    .accessibilityLabel(ui.reading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
    }
}
