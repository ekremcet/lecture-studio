import SwiftUI
import StudioCore

/// Who is presenting. Saved as `studio.json` at the root of the lecture repository.
struct ProfileSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p = Profile.empty()
    @State private var contact = ""
    @State private var unitLabel = "week"
    @State private var busy = false

    var firstRun: Bool { store.profileExists == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: firstRun ? "Who is presenting?" : "Presenter profile", icon: "person", description: firstRun
                ? "Title slides, closing slides, and the agent's tone come from this. Saved in the repository, so it travels with your material. You can change it any time."
                : "Used on title and closing slides of new decks and sent to the agent as context. Saved as studio.json at the repository root.")
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Name") { TextField("Ada Lovelace", text: $p.name) }
                LabeledField(label: "Email") { TextField("ada@example.edu", text: bind(\.email)) }
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Affiliation") { TextField("University, company, or event", text: bind(\.affiliation)) }
                LabeledField(label: "Department or role") { TextField("Department of Computer Science", text: bind(\.unit)) }
            }
            LabeledField(label: "Contact lines for the closing slide", hint: "One per line. \"Label: value\" becomes a bold label, e.g. \"Office hours: Tuesday 14:00-16:00, Room B21\".") {
                TextEditor(text: $contact).font(.system(.caption, design: .monospaced)).frame(height: 64).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Default language") { TextField("English", text: bind(\.language)) }
                LabeledField(label: "A course is made of…") { UnitPicker(value: $unitLabel) }
            }
            LabeledField(label: "How you teach or speak", hint: "Principles, pacing, tone, what to avoid. The agent follows this when it writes. A few lines are enough.") {
                TextEditor(text: bind(\.style)).font(.body).frame(height: 110).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }
            HStack {
                Spacer()
                Button(firstRun ? "Later" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { save() } label: { BusyLabel(busy: busy, idle: "Save profile", working: "Saving…") }.buttonStyle(.borderedProminent).disabled(busy || p.name.trimmed.isEmpty)
            }
        }
        .dialogFrame(width: 600)
        .onAppear {
            p = store.profile ?? .empty()
            if (p.language ?? "").isEmpty { p.language = "English" }
            contact = (p.contact ?? []).joined(separator: "\n")
            unitLabel = p.unitLabel ?? "week"
        }
    }

    func bind(_ k: WritableKeyPath<Profile, String?>) -> Binding<String> {
        Binding(get: { p[keyPath: k] ?? "" }, set: { p[keyPath: k] = $0 })
    }

    func save() {
        guard let fs = store.repo else { return }
        busy = true
        var out = p
        out.contact = contact.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
        out.unitLabel = unitLabel
        do {
            let saved = try ProfileStore(fs: fs).write(out)
            store.profile = saved
            store.profileExists = true
            store.toasts.success("Profile saved", "studio.json at the repository root")
            Task { await store.refreshFiles() }
            dismiss()
        } catch { store.toasts.error("Could not save the profile", error) }
        busy = false
    }
}
