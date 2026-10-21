import SwiftUI
import StudioCore

/// Find and replace over the editor, in the manner of Xcode's find bar: matches highlight as you type,
/// Return steps to the next one (⇧Return the previous), Escape closes the bar. The replace row shows
/// with Find and Replace (⌥⌘F) or the chevron.
struct FindBar: View {
    @Environment(StudioStore.self) private var store
    let editor: EditorController
    @FocusState private var focus: Field?

    enum Field { case find, replace }

    var body: some View {
        @Bindable var find = editor.find
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button { find.replacing.toggle() } label: { Image(systemName: find.replacing ? "chevron.down" : "chevron.right").frame(width: 12) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(find.replacing ? "Hide replace" : "Show replace")
                TextField("Find", text: $find.text)
                    .focused($focus, equals: .find)
                    .onKeyPress(.return, phases: .down) { press in editor.findNext(backwards: press.modifiers.contains(.shift)); return .handled }
                    .onKeyPress(.escape) { editor.closeFind(focusEditor: true); return .handled }
                Text(find.label).monospacedDigit().lineLimit(1).fixedSize()
                    .foregroundStyle(find.status.invalid || (find.status.count == 0 && !find.text.isEmpty) ? .red : .secondary)
                options
                ControlGroup {
                    Button { editor.findNext(backwards: true) } label: { Image(systemName: "chevron.left") }.help("Previous match" + hint(.findPrevious))
                    Button { editor.findNext() } label: { Image(systemName: "chevron.right") }.help("Next match" + hint(.findNext))
                }
                .fixedSize()
                .disabled(find.status.count == 0)
                Button("Done") { editor.closeFind(focusEditor: true) }
            }
            if find.replacing {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 12, height: 1)
                    TextField("Replace", text: $find.replacement)
                        .focused($focus, equals: .replace)
                        .onKeyPress(.return, phases: .down) { _ in editor.replaceNext(); return .handled }
                        .onKeyPress(.escape) { editor.closeFind(focusEditor: true); return .handled }
                    Button("Replace") { editor.replaceNext() }.help("Replace this match and go to the next")
                        .disabled(find.status.count == 0)
                    Button("All") { replaceAll() }.help("Replace every match in this file (one undo)")
                        .disabled(find.status.count == 0)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .onAppear { focus = .find }
        .onChange(of: find.focusRequest) { _, _ in focus = .find }
        .onChange(of: find.text) { _, _ in editor.updateFind() }
        .onChange(of: find.replacement) { _, _ in editor.updateFind() }
        .onChange(of: find.caseSensitive) { _, _ in editor.updateFind() }
        .onChange(of: find.wholeWord) { _, _ in editor.updateFind() }
        .onChange(of: find.regexp) { _, _ in editor.updateFind() }
    }

    var options: some View {
        @Bindable var find = editor.find
        return Menu {
            Toggle("Match Case", isOn: $find.caseSensitive)
            Toggle("Whole Words", isOn: $find.wholeWord)
            Toggle("Regular Expression", isOn: $find.regexp)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .symbolVariant(find.caseSensitive || find.wholeWord || find.regexp ? .fill : .none)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Match case, whole words, regular expression. With a regular expression, $1 in the replacement is the first group.")
    }

    func hint(_ a: ShortcutAction) -> String { store.shortcut(for: a).map { " (\($0.display))" } ?? "" }

    func replaceAll() {
        Task {
            let n = await editor.replaceAll()
            if n > 0 { store.toasts.success(n == 1 ? "Replaced 1 match" : "Replaced \(n) matches") }
        }
    }
}
