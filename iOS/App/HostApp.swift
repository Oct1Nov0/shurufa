import SwiftUI

// The containing app. iOS needs one to carry the keyboard extension; this one
// only says how to switch the keyboard on and gives a field to try it in.
@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

struct HomeView: View {
    @State private var text = ""

    private let steps = [
        "打开「设置」→「通用」→「键盘」→「键盘」→「添加新键盘」。",
        "在第三方键盘里选择「中日键盘」。",
        "回到任意输入框，长按地球键，切换到「中日键盘」。",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("启用步骤") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
                Section("试打") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                Section {
                    Text("键盘不需要「允许完全访问」，所有输入都在本机处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("中日键盘")
        }
    }
}
