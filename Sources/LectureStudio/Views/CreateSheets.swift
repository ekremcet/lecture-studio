import SwiftUI
import AppKit
import StudioCore

/// New course.
struct NewCourseSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var language = ""
    @State private var semester = ""
    @State private var unitPrefix = "week"
    @State private var withSyllabus = true
    @State private var withContext = true
    @State private var busy = false
    @State private var folder = ""
    @State private var folderEdited = false
    @State private var location: URL?

    var suggestedFolder: String { name.isEmpty ? "" : Scaffold.defaultFolder(code: code, name: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "New course", description: "Creates the course folder in the repository, with a syllabus and a context file for the agent to fill in. Add sources and \(unitPrefix)s next.")
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Code", hint: "optional") { TextField("CS101", text: $code).onChange(of: code) { _, v in code = v.uppercased() } }.frame(width: 140)
                LabeledField(label: "Name") { TextField("Data Structures and Algorithms", text: $name) }
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Language") { TextField("English", text: $language) }
                LabeledField(label: "Term") { TermPicker(text: $semester) }
                LabeledField(label: "Made of") { UnitPicker(value: $unitPrefix) }
            }
            LabeledField(label: "Folder", hint: location.map { "Course files live in \($0.path); the library keeps a link named \(folder)." } ?? "Inside the library (\(store.repo?.root.lastPathComponent ?? "library")). Lowercase letters, digits, dots, dashes. Filled from the code and name until you edit it, or choose a folder anywhere.") {
                HStack {
                    TextField(suggestedFolder.isEmpty ? "folder-name" : suggestedFolder, text: $folder).font(.system(.body, design: .monospaced))
                        .onChange(of: folder) { _, v in folderEdited = !v.isEmpty && v != suggestedFolder }
                    Button("Choose…") { chooseFolder(store: store, folder: $folder, location: $location, edited: $folderEdited) }
                }
            }
            .onChange(of: suggestedFolder) { _, v in if !folderEdited { folder = v } }
            Toggle("Create syllabus.md", isOn: $withSyllabus)
            Toggle("Create AGENTS.md (course context the assistant reads)", isOn: $withContext)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Create course", working: "Creating…") }.buttonStyle(.borderedProminent).disabled(busy || name.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame()
        .onAppear { language = store.profile?.language ?? "English"; unitPrefix = store.profile?.unitLabel ?? "week" }
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        do {
            let r = try Scaffold(fs: fs).lecture(code: code, name: name, language: language, semester: semester, unitPrefix: unitPrefix, withSyllabus: withSyllabus, withContext: withContext, folder: folder, location: location)
            store.toasts.success("Course created", r.course)
            dismiss()
            Task { await store.refreshFiles(); store.selectCourse(r.course) }
        } catch { store.toasts.error("Could not create the course", error) }
        busy = false
    }
}

struct NewTalkSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var event = ""
    @State private var language = ""
    @State private var busy = false
    @State private var folder = ""
    @State private var folderEdited = false
    @State private var location: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "New talk", description: "One deck in its own folder, with a title slide, agenda, takeaways, and a closing slide from your profile. Drop the material it should draw on into its sources next.")
            LabeledField(label: "Title") { TextField("AI in Science", text: $name) }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Event or venue", hint: "optional") { TextField("Research Seminar, December 2026", text: $event) }
                LabeledField(label: "Language") { TextField("English", text: $language) }
            }
            LabeledField(label: "Folder", hint: location.map { "Talk files live in \($0.path); the library keeps a link named \(folder)." } ?? "Inside the library. The deck is \(folder.isEmpty ? "…" : "\(folder)/\(folder).md"). Filled from the title until you edit it, or choose a folder anywhere.") {
                HStack {
                    TextField(slug(name).isEmpty ? "folder-name" : slug(name), text: $folder).font(.system(.body, design: .monospaced))
                        .onChange(of: folder) { _, v in folderEdited = !v.isEmpty && v != slug(name) }
                    Button("Choose…") { chooseFolder(store: store, folder: $folder, location: $location, edited: $folderEdited) }
                }
            }
            .onChange(of: name) { _, v in if !folderEdited { folder = slug(v) } }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Create talk", working: "Creating…") }.buttonStyle(.borderedProminent).disabled(busy || name.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame()
        .onAppear { language = store.profile?.language ?? "English" }
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        do {
            let r = try Scaffold(fs: fs).talk(name: name, event: event, date: nil, language: language, folder: folder, location: location)
            store.toasts.success("Talk created", r.deck)
            dismiss()
            Task {
                await store.refreshFiles()
                store.course = r.course
                store.unit = ""
                await store.refreshSourceCount()
                await store.openFile(r.deck, select: false)
            }
        } catch { store.toasts.error("Could not create the talk", error) }
        busy = false
    }
}

struct NewUnitSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var week = 1
    @State private var topic = ""
    @State private var withGuide = true
    @State private var busy = false
    @State private var meta: CourseMeta?

    var word: String { meta?.unitPrefix ?? "week" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "New \(word)", description: "Creates \(word)\(meta?.unitSep ?? "")\(week)/\(word)\(meta?.unitSep ?? "")\(week)-slides.md with the house front matter\(meta?.courseName.isEmpty == false ? " for \(meta!.code) - \(meta!.courseName)" : ""), a title slide, recap, agenda, and closing slides, plus an empty assets/ folder.")
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: word.capFirst) { TextField("", value: $week, format: .number).frame(width: 60) }
                LabeledField(label: "Topic") { TextField("Stack and Queue", text: $topic) }
            }
            Toggle("Also create the instructor guide", isOn: $withGuide)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Create \(word)", working: "Creating…") }.buttonStyle(.borderedProminent).disabled(busy || topic.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame()
        .task {
            guard let fs = store.repo else { return }
            let c = store.course
            let m = await Task.detached { courseMeta(fs: fs, course: c) }.value
            meta = m
            week = (m.weeks.last ?? 0) + 1
        }
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        do {
            let r = try Scaffold(fs: fs).week(course: store.course, week: week, topic: topic, withGuide: withGuide)
            store.toasts.success("\(word.capFirst) \(week) created", r.created.joined(separator: ", "))
            dismiss()
            Task {
                await store.refreshFiles()
                store.unit = r.unit
                await store.refreshSourceCount()
                await store.openFile(r.deck, select: false)
            }
        } catch { store.toasts.error("Could not create the \(word)", error) }
        busy = false
    }
}

struct NewFileSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var title = ""
    @State private var kind = "md"
    @State private var busy = false

    var body: some View {
        let unit = store.unit ?? ""
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "New file", description: "In \(unit.isEmpty ? store.course : "\(store.course)/\(unit)").")
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Type") {
                    Picker("", selection: $kind) { Text("Markdown").tag("md"); Text("Marp deck").tag("deck") }.labelsHidden()
                }.frame(width: 150)
                LabeledField(label: "File name", hint: ".md is added when missing") { TextField(kind == "deck" ? "extra-slides" : "lab-3", text: $name) }
            }
            LabeledField(label: kind == "deck" ? "Topic" : "Title") { TextField(kind == "deck" ? "Topic of the deck" : "Heading of the document", text: $title) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Create file", working: "Creating…") }.buttonStyle(.borderedProminent).disabled(busy || name.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame()
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        do {
            let r = try Scaffold(fs: fs).file(course: store.course, unit: store.unit ?? "", name: name, kind: kind, title: title)
            store.toasts.success("File created", r.path)
            dismiss()
            Task { await store.refreshFiles(); await store.openFile(r.path, select: false) }
        } catch { store.toasts.error("Could not create the file", error) }
        busy = false
    }
}

struct EditLectureSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var code = ""
    @State private var term = ""
    @State private var folder = ""
    @State private var unitPrefix = "week"
    @State private var talk = false
    @State private var busy = false
    @State private var newLocation: URL?

    var renaming: Bool { folder.trimmed != store.course || newLocation != nil }
    var currentPath: String { (try? store.repo?.resolve(store.course).path) ?? store.course }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: talk ? "Edit talk" : "Edit course", description: talk
                ? "The title and event are shown in the studio and saved in \(store.course)/studio.json. The deck itself is not changed; ask the agent for that."
                : "The title and code are shown in the studio and saved in \(store.course)/studio.json. Deck headers are not changed; ask the agent for that.")
            HStack(alignment: .top, spacing: 12) {
                if !talk { LabeledField(label: "Code") { TextField("CS231", text: $code).onChange(of: code) { _, v in code = v.uppercased() } }.frame(width: 140) }
                LabeledField(label: "Title") { TextField(talk ? "AI in Science" : "Data Structures and Algorithms", text: $title) }
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: talk ? "Event" : "Term") { if talk { TextField("Research Seminar, December 2026", text: $term) } else { TermPicker(text: $term) } }
                if !talk { LabeledField(label: "Made of", hint: "New units get this prefix. Existing folders keep their names.") { UnitPicker(value: $unitPrefix) } }
            }
            Toggle("This is a talk: one deck, no numbered units", isOn: $talk)
            LabeledField(label: "Folder", hint: newLocation.map { "Will move to \($0.path); the library keeps a link named \(folder)." } ?? (renaming ? "Will be renamed to \(folder) (with git mv when tracked). Links that point at the old path, on GitHub or in other files, stop working." : "Choose a folder to move the course elsewhere: inside the library it is a rename, outside the library the files move there and the library keeps a link.")) {
                HStack {
                    Text(newLocation?.path ?? currentPath).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseMove() }
                    if renaming { Button("Keep") { folder = store.course; newLocation = nil } }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: renaming ? "Save and move folder" : "Save", working: "Saving…") }.buttonStyle(.borderedProminent).tint(renaming ? .red : .accentColor).disabled(busy || title.trimmed.isEmpty)
            }
        }
        .dialogFrame()
        .onAppear {
            let m = store.meta
            let c = store.course
            talk = m?.kind == .talk
            title = m?.title ?? Rx("^[a-z]{2,4}\\d{3,4}-?", .caseInsensitive).replace(c, with: "").replacingOccurrences(of: "-", with: " ")
            code = m?.code ?? Labels.courseCode(c)
            term = m?.term ?? ""
            folder = c
            unitPrefix = Labels.unitWord(m)
        }
    }

    /// Pick where the course should live: a top-level folder of the library (a rename), or anywhere else (a move plus a link).
    func chooseMove() {
        guard let root = store.repo?.root else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = root
        p.prompt = "Move here"
        p.message = "Choose or create the folder the course should move to. Inside \(root.lastPathComponent) this renames it; elsewhere the files move and the library keeps a link."
        guard p.runModal() == .OK, let u = p.url else { return }
        let path = u.standardizedFileURL.path
        if path == root.path || path == currentPath { newLocation = nil; folder = store.course; return }
        if path.hasPrefix(root.path + "/") {
            let rel = String(path.dropFirst(root.path.count + 1))
            if rel.contains("/") { store.toasts.error("Courses are top-level folders of the library", "\(rel) is nested; choose a folder directly under \(root.lastPathComponent)."); return }
            let inside = (try? FileManager.default.contentsOfDirectory(atPath: path))?.filter { !$0.hasPrefix(".") } ?? []
            if !inside.isEmpty { store.toasts.error("That folder is not empty", rel); return }
            try? FileManager.default.removeItem(at: u)   // the rename creates it again
            folder = rel
            newLocation = nil
        } else {
            folder = store.course
            newLocation = u
        }
    }

    func submit() {
        guard let fs = store.repo else { return }
        busy = true
        Task {
            do {
                let r = try await Scaffold(fs: fs).editLecture(course: store.course, title: title, code: talk ? "" : code, term: term, newFolder: folder, unitPrefix: talk ? nil : unitPrefix, kind: talk ? .talk : .course, newLocation: newLocation)
                store.toasts.success("Lecture updated", r.course)
                dismiss()
                await store.refreshFiles()
                store.course = r.course
            } catch { store.toasts.error("Could not update the lecture", error) }
            busy = false
        }
    }
}


/// Bring an existing course folder or a single deck into the library.
struct ImportCourseSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var code = ""
    @State private var folder = ""
    @State private var talk = false
    @State private var move = false
    @State private var busy = false

    var source: URL? { store.importSource }
    var isFile: Bool {
        guard let u = source else { return false }
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && !d.boolValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: isFile ? "Import deck as a talk" : "Import course", description: isFile
                ? "The deck is copied into its own folder in the library, with an assets folder next to it. The original stays where it is unless you choose to move it."
                : "The folder is copied into the library as it is; numbered units such as week1, week2 are recognised. The original stays where it is unless you choose to move it.")
            if let u = source {
                Label(u.path, systemImage: isFile ? "doc.text" : "folder").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Code", hint: "optional") { TextField("CS101", text: $code).onChange(of: code) { _, v in code = v.uppercased() } }.frame(width: 140)
                LabeledField(label: "Title") { TextField("Data Structures and Algorithms", text: $title) }
            }
            LabeledField(label: "Folder in the library", hint: "Lowercase letters, digits, dots, dashes.") {
                TextField("folder-name", text: $folder).font(.system(.body, design: .monospaced))
            }
            if !isFile { Toggle("This is a talk: one deck, no numbered units", isOn: $talk) }
            Toggle("Move instead of copy", isOn: $move)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { submit() } label: { BusyLabel(busy: busy, idle: move ? "Move into library" : "Import", working: "Importing…") }.buttonStyle(.borderedProminent).disabled(busy || folder.trimmed.isEmpty || title.trimmed.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame()
        .onAppear {
            guard let u = source else { return }
            let base = isFile ? u.deletingPathExtension().lastPathComponent : u.lastPathComponent
            folder = slug(base)
            title = Labels.courseTitle(slug(base))
            code = Labels.courseCode(slug(base))
            talk = isFile
        }
    }

    func submit() {
        guard let fs = store.repo, let u = source else { return }
        busy = true
        let (f, t, c, k, m) = (folder.trimmed, title, code, (talk || isFile) ? LectureKind.talk : LectureKind.course, move)
        Task {
            do {
                let r = try await Task.detached { try Scaffold(fs: fs).importCourse(from: u, folder: f, title: t, code: c, kind: k, move: m) }.value
                store.toasts.success(move ? "Moved into the library" : "Imported", r.course)
                store.importSource = nil
                dismiss()
                await store.refreshFiles()
                store.selectCourse(r.course)
            } catch { store.toasts.error("Could not import", error) }
            busy = false
        }
    }
}


/// Pick a folder for a new course or talk. Inside the library it must be a top-level folder; anywhere
/// else the library gets a link to it, so the material can live in another location.
@MainActor
func chooseFolder(store: StudioStore, folder: Binding<String>, location: Binding<URL?>, edited: Binding<Bool>) {
    guard let root = store.repo?.root else { return }
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.canCreateDirectories = true
    p.directoryURL = root
    p.prompt = "Use this folder"
    p.message = "Choose or create the folder for this course. Inside \(root.lastPathComponent) it is used directly; elsewhere the library links to it."
    guard p.runModal() == .OK, let u = p.url else { return }
    let path = u.standardizedFileURL.path
    if path == root.path { store.toasts.error("Choose a folder inside the library, not the library itself"); return }
    if path.hasPrefix(root.path + "/") {
        let rel = String(path.dropFirst(root.path.count + 1))
        if rel.contains("/") { store.toasts.error("Courses are top-level folders of the library", "\(rel) is nested; choose a folder directly under \(root.lastPathComponent)."); return }
        folder.wrappedValue = rel
        location.wrappedValue = nil
    } else {
        folder.wrappedValue = slug(u.lastPathComponent)
        location.wrappedValue = u
    }
    edited.wrappedValue = true
}
