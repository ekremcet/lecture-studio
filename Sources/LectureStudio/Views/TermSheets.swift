import SwiftUI
import StudioCore

/// A new semester of the open course: the folder is copied, deck dates move to the new start date,
/// the old term is archived.
struct NewTermSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var folder = ""
    @State private var startDate = Date()
    @State private var copyUnits = true
    @State private var archiveOld = true
    @State private var busy = false

    var from: String { store.course }
    var word: String { store.word }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "New term of \(Labels.courseTitle(from, store.meta))", icon: "calendar.badge.plus", description: "Copies \(from) into a new folder. Every \(word) deck comes along, with its dates moved so that \(word) 1 falls on the first lecture and the others follow weekly. Sources are copied too and can be indexed for the new term. Exported PDFs are left behind.")
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Term") { TermPicker(text: $term).onChange(of: term) { _, v in if !folderEdited { folder = suggested(v) } } }
                LabeledField(label: "First lecture", hint: "\(word.capFirst) 1 gets this date; \(word) N is \(word) 1 plus N-1 weeks.") { DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden() }
            }
            LabeledField(label: "New folder", hint: "Inside the library. Lowercase letters, digits, dots, dashes.") {
                TextField("cs221-fall26", text: $folder).font(.system(.body, design: .monospaced)).onChange(of: folder) { _, v in folderEdited = !v.isEmpty && v != suggested(term) }
            }
            Toggle("Copy the \(word)s and their decks (off: only the syllabus, context and sources)", isOn: $copyUnits)
            Toggle("Archive \(from) afterwards", isOn: $archiveOld)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Create term", working: "Copying…") }.buttonStyle(.borderedProminent).disabled(busy || term.trimmed.isEmpty || folder.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame(width: 560)
        .onAppear {
            // Guess the next term from the current one: "Fall 2025" -> "Fall 2026".
            term = TermValue.parse(store.meta?.term ?? "")?.next.text ?? TermValue(season: "Fall", year: Calendar.current.component(.year, from: Date())).text
            folder = suggested(term)
        }
    }

    @State private var folderEdited = false

    /// "cs221-fall25" + "Fall 2026" -> "cs221-fall26"; otherwise "<folder>-<term>".
    func suggested(_ t: String) -> String {
        let termSlug = slug(t.replacingOccurrences(of: "20", with: "").replacingOccurrences(of: " ", with: ""))
        if termSlug.isEmpty { return "" }
        let base = Rx("-(fall|spring|summer|winter|guz|bahar|yaz)[-]?\\d{2,4}$", .caseInsensitive).replace(from, with: "")
        return "\(base)-\(termSlug)"
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        let (f, t, d, cu, ao, src) = (folder.trimmed, term.trimmed, startDate, copyUnits, archiveOld, from)
        Task {
            do {
                let r = try await Terms.newTerm(fs: fs, from: src, folder: f, term: t, startDate: d, copyUnits: cu, archiveOld: ao)
                store.toasts.success("Term created", "\(r.course): \(r.units.count) \(word)s, \(r.redated) decks redated")
                dismiss()
                await store.refreshFiles()
                store.selectCourse(r.course)
            } catch { store.toasts.error("Could not create the term", error) }
            busy = false
        }
    }
}

/// Unit-by-unit comparison of two terms, with a line diff of a chosen deck.
struct CompareSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var other = ""
    @State private var rows: [Compare.UnitCompare] = []
    @State private var selected: Compare.UnitCompare?
    @State private var diff: [Compare.DiffLine] = []
    @State private var busy = false

    /// Only the other terms of this same course (linked through "New term from this course").
    var candidates: [String] { store.terms(of: store.course).filter { $0 != store.course } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeader(title: "Compare terms", icon: "arrow.left.arrow.right", description: "Each \(store.word) of \(Labels.courseLabel(store.course, store.meta)) \(store.meta?.term ?? "") against the same \(store.word) of another term of this course. Pick a \(store.word) to see the changed lines of its deck.")
            if candidates.isEmpty {
                Label("This course has no other term yet. Use \"New term from this course…\" to create one; terms made that way are linked and can be compared here.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Against").font(.callout)
                Picker("", selection: $other) {
                    Text("Choose a term").tag("")
                    ForEach(candidates, id: \.self) { c in Text((store.lectures[c]?.term ?? c) + (store.lectures[c]?.archived == true ? " (archived)" : "")).tag(c) }
                }.labelsHidden().fixedSize().disabled(candidates.isEmpty).onChange(of: other) { _, _ in load() }
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if let s = selected { Text("\(s.unit): +\(s.added) −\(s.removed) lines").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        Button { select(r) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(color(r.change)).frame(width: 8, height: 8)
                                Text(Labels.unitLabel(r.unit)).font(.callout).frame(width: 90, alignment: .leading)
                                Text(label(r)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(selected?.unit == r.unit ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if rows.isEmpty && !other.isEmpty && !busy { Text("No \(store.word)s to compare.").font(.caption).foregroundStyle(.secondary).padding() }
                    Spacer(minLength: 0)
                }
                .frame(width: 300)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if diff.isEmpty { Text(selected == nil ? "Pick a \(store.word) on the left." : "Identical.").font(.caption).foregroundStyle(.secondary).padding() }
                        ForEach(Array(diff.enumerated()), id: \.offset) { _, l in
                            if l.kind != .same || showContext {
                                Text((l.kind == .added ? "+ " : l.kind == .removed ? "− " : "  ") + l.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(l.kind == .same ? Color.secondary : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(l.kind == .added ? Color.green.opacity(0.15) : l.kind == .removed ? Color.red.opacity(0.15) : Color.clear)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(minHeight: 380, maxHeight: 520)
            HStack {
                Toggle("Show unchanged lines", isOn: $showContext).controlSize(.small)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .dialogFrame(width: 900)
        .onAppear {
            if let from = store.meta?.derivedFrom, candidates.contains(from) { other = from; load() }
            else if let prev = candidates.first { other = prev; load() }
        }
    }

    @State private var showContext = false

    func color(_ c: Compare.Change) -> Color { c == .same ? .secondary.opacity(0.4) : c == .changed ? .orange : c == .onlyRight ? .green : .red }
    func label(_ r: Compare.UnitCompare) -> String {
        switch r.change {
        case .same: return "same"
        case .changed: return "+\(r.added) −\(r.removed) lines"
        case .onlyLeft: return "only in \(store.lectures[other]?.term ?? other)"
        case .onlyRight: return "only in this term"
        }
    }

    func load() {
        guard let fs = store.repo, !other.isEmpty else { rows = []; return }
        busy = true
        selected = nil; diff = []
        let (l, r) = (other, store.course)
        Task {
            rows = await Task.detached { Compare.units(fs: fs, left: l, right: r) }.value
            busy = false
        }
    }

    func select(_ r: Compare.UnitCompare) {
        guard let fs = store.repo else { return }
        selected = r
        let a = r.leftDeck.flatMap { $0.isEmpty ? nil : try? fs.readString($0) } ?? ""
        let b = r.rightDeck.flatMap { $0.isEmpty ? nil : try? fs.readString($0) } ?? ""
        Task { diff = await Task.detached { Compare.lines(a, b) }.value }
    }
}


/// Remove a course or talk. The safe choice hides it and leaves the folder untouched; moving the
/// folder to the Trash is a separate, confirmed step and can be undone from the Trash.
struct RemoveCourseSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var trash = false
    @State private var confirmText = ""

    var name: String { store.course }
    var label: String { Labels.courseLabel(name, store.meta) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Remove \(label)", icon: "trash", description: "Choose what should happen to the folder \(name).")
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { !trash }, set: { trash = !$0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove from the studio only").font(.callout.weight(.medium))
                        Text("The folder and every file in it stay where they are. It can be shown again from Settings > Library.").font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.radioGroupStyle)
                Toggle(isOn: $trash) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move the folder to the Trash").font(.callout.weight(.medium)).foregroundStyle(.red)
                        Text("Decks, sources, assets, everything in \(name) goes to the Trash. Recoverable from there until the Trash is emptied.").font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.radioGroupStyle)
            }
            if trash {
                LabeledField(label: "Type the folder name to confirm") { TextField(name, text: $confirmText).font(.system(.body, design: .monospaced)) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if trash {
                    Button("Move to Trash", role: .destructive) { store.trashCourse(name); dismiss() }.buttonStyle(.borderedProminent).tint(.red).disabled(confirmText.trimmed != name)
                } else {
                    Button("Remove from studio") { store.setExcluded(name, true); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .dialogFrame()
    }
}

/// Two mutually exclusive toggles drawn as radio buttons.
struct RadioGroupToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn = true } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: configuration.isOn ? "largecircle.fill.circle" : "circle").foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary).padding(.top, 2)
                configuration.label
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
extension ToggleStyle where Self == RadioGroupToggleStyle { static var radioGroupStyle: RadioGroupToggleStyle { RadioGroupToggleStyle() } }
