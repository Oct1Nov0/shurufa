import SwiftUI

/// The words added by hand: letters and the word they type. Saved to the
/// container the keyboard reads; the keyboard picks up changes when it opens.
struct DictionaryView: View {
    @State private var words: [UserWord] = []
    @State private var editing: UserWord?
    @State private var error = ""

    var body: some View {
        Form {
            Section {
                if UserDictionary.available {
                    Label("共享存储可用，键盘下次弹出时读取改动。", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("共享存储不可用，键盘读不到这里的词。", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            Section("字母可填首字母或全拼") {
                ForEach(words) { entry in
                    Button { editing = entry } label: {
                        HStack {
                            Text(entry.code).foregroundStyle(.secondary).monospaced()
                            Spacer()
                            Text(entry.word).foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { offsets in words.remove(atOffsets: offsets); save() }
            }
        }
        .navigationTitle("自定义词库")
        .toolbar {
            Button { editing = UserWord(code: "", word: "") } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { entry in
            WordEditor(entry: entry) { changed in
                if let index = words.firstIndex(where: { $0.id == changed.id }) { words[index] = changed } else { words.append(changed) }
                save()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let saved = UserDictionary.load() {
            words = saved
        } else {
            // First run: the starter words, written so the keyboard has them too.
            words = UserDictionary.starters
            save()
        }
    }

    private func save() {
        do { try UserDictionary.save(words); error = "" } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
}

private struct WordEditor: View {
    @State var entry: UserWord
    var onSave: (UserWord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("字母，例如 gsw", text: $entry.code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("词，例如 告诉我", text: $entry.word)
            }
            .navigationTitle("编辑词条")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        entry.code = UserDictionary.normalised(entry.code)
                        entry.word = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(UserDictionary.normalised(entry.code).isEmpty || entry.word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
