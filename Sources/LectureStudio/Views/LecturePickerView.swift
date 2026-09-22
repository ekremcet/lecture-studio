import SwiftUI
import AppKit
import UniformTypeIdentifiers
import StudioCore

/// First screen: one card per course or talk.
struct LecturePickerView: View {
    @Environment(StudioStore.self) private var store

    struct CourseCard: Identifiable { var course: String; var units: Set<String>; var decks: Int; var files: Int; var modified: Double; var id: String { course } }

    enum Sort: String, CaseIterable, Identifiable {
        case term, edited, name, custom
        var id: String { rawValue }
        var label: String { switch self { case .term: return "Newest term"; case .edited: return "Last edited"; case .name: return "Name"; case .custom: return "My order" } }
    }
    @State private var sort: Sort = Sort(rawValue: AppSettings.courseSort) ?? .term
    @State private var customOrder: [String] = AppSettings.courseOrder

    var cards: [CourseCard] {
        var map: [String: CourseCard] = [:]
        for f in store.files {
            var c = map[f.course] ?? CourseCard(course: f.course, units: [], decks: 0, files: 0, modified: 0)
            if !f.unit.isEmpty { c.units.insert(f.unit) }
            if f.kind == .deck { c.decks += 1 }
            c.files += 1
            c.modified = max(c.modified, f.modified)
            map[f.course] = c
        }
        let list = Array(map.values)
        func title(_ c: CourseCard) -> String { Labels.courseLabel(c.course, store.lectures[c.course]).lowercased() }
        let sorted: [CourseCard]
        switch sort {
        case .term:
            // Newest term first; talks and courses without a term after them, by name.
            sorted = list.sorted { a, b in
                let ta = TermValue.parse(store.lectures[a.course]?.term ?? "")?.order ?? -1
                let tb = TermValue.parse(store.lectures[b.course]?.term ?? "")?.order ?? -1
                return ta != tb ? ta > tb : title(a) < title(b)
            }
        case .edited: sorted = list.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : title($0) < title($1) }
        case .name: sorted = list.sorted { title($0) < title($1) }
        case .custom:
            let idx = Dictionary(uniqueKeysWithValues: customOrder.enumerated().map { ($1, $0) })
            sorted = list.sorted { (idx[$0.course] ?? Int.max, title($0)) < (idx[$1.course] ?? Int.max, title($1)) }
        }
        // The library root's loose files always come last.
        return sorted.filter { $0.course != "(root)" } + sorted.filter { $0.course == "(root)" }
    }

    func move(_ course: String, by delta: Int) {
        var order = cards.filter { !isArchived($0) && $0.course != "(root)" }.map(\.course)
        guard let i = order.firstIndex(of: course) else { return }
        let j = max(0, min(order.count - 1, i + delta))
        order.remove(at: i); order.insert(course, at: j)
        customOrder = order
        AppSettings.courseOrder = order
        if sort != .custom { sort = .custom; AppSettings.courseSort = sort.rawValue }
    }

    let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)]
    @State private var showArchived = false

    func isArchived(_ c: CourseCard) -> Bool { store.lectures[c.course]?.archived == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LECTURE STUDIO").font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(.secondary)
                        Text("What are you preparing?").font(.title.weight(.semibold))
                        Text("Your courses and talks, written as Marp Markdown: plain text files that render as slides. Keep your sources next to them; an assistant is one click away for outlines, drafts, checks and speaker notes, and every change stays in your hands.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack {
                        Button { pickImport() } label: { Label("Import…", systemImage: "square.and.arrow.down") }.help("Bring an existing course folder or a deck file into the library")
                        Button { store.dialog = .sources } label: { Label("Shared sources", systemImage: "book") }.help("Sources every lecture and talk can use")
                        Button { store.dialog = .profile } label: { Label(store.profileExists == true ? (store.profile?.name ?? "Profile") : "Set up your profile", systemImage: "person") }.help("Name, contact lines, teaching style")
                        Button { Task { await store.refreshLibrary() } } label: { Image(systemName: "arrow.clockwise") }.help("Read the library folder again (⌘R). Changes from other apps normally show up on their own.")
                    }
                }
                if let c = store.checklist { GettingStartedView(state: c) }
                HStack {
                    Spacer()
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.label).tag($0) } }
                        .fixedSize().controlSize(.small)
                        .onChange(of: sort) { _, v in AppSettings.courseSort = v.rawValue }
                        .help(sort == .custom ? "Drag a card onto another, or use the card's menu, to arrange them" : "Order of the courses and talks")
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    DashedCard(icon: "plus", title: "New course", description: "A folder of numbered sessions, with a syllabus and a context file") { store.dialog = .lecture }
                    DashedCard(icon: "mic", title: "New talk", description: "One deck for a seminar, keynote, workshop, or pitch") { store.dialog = .talk }
                    if !store.filesLoaded {
                        ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(minHeight: 128).redacted(reason: .placeholder) }
                    }
                    ForEach(cards.filter { !isArchived($0) }) { c in courseCard(c) }
                }
                let archived = cards.filter { isArchived($0) }
                if !archived.isEmpty {
                    DisclosureGroup(isExpanded: $showArchived) {
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(archived) { c in courseCard(c) } }.padding(.top, 8)
                    } label: {
                        Label("Archived (\(archived.count))", systemImage: "archivebox").font(.headline).foregroundStyle(.secondary)
                    }
                }
                if store.filesLoaded && cards.isEmpty {
                    EmptyBlock(icon: "folder", title: "No courses or talks yet", description: "Start with New course or New talk above. Each one gets its own folder in the repository, a deck scaffold with your name on it, and a place for its sources.")
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 36)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    /// A folder of decks, or one .md deck. The sheet asks for the title and where it goes.
    func pickImport() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.folder, .plainText, .init(filenameExtension: "md") ?? .plainText]
        p.allowsMultipleSelection = false
        p.prompt = "Import"
        p.message = "Choose a course folder or a single Marp deck (.md)"
        guard p.runModal() == .OK, let u = p.url else { return }
        store.importSource = u
        store.dialog = .importCourse
    }

    func courseCard(_ c: CourseCard) -> some View {
        let root = c.course == "(root)"
        let meta = store.lectures[c.course]
        let talk = Labels.isTalk(meta)
        let word = Labels.unitWord(meta, units: Array(c.units))
        let code = root ? "" : Labels.courseCode(c.course, meta)
        return Button { store.selectCourse(c.course) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: root ? "folder" : talk ? "mic" : "graduationcap")
                    if !code.isEmpty { Text(code).font(.system(.caption, design: .monospaced)) }
                    Spacer()
                    if meta?.archived == true { Chip(text: "Archived") }
                    if let term = meta?.term, !term.isEmpty { Text(term).font(.caption) }
                }
                .foregroundStyle(.secondary)
                Text(root ? "Repository files" : Labels.courseTitle(c.course, meta)).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if !c.units.isEmpty && !talk { Chip(text: Labels.plural(word, c.units.count), filled: true) }
                    Chip(text: "\(c.decks) decks", icon: "rectangle.on.rectangle", filled: true)
                    Chip(text: "\(c.files) files")
                    if let r = store.publishRecords[c.course] {
                        let published = Set(r.files.keys.compactMap { Int($0.split(separator: "/").first ?? "") }.filter { $0 > 0 }).count
                        Chip(text: talk || published == 0 ? "published" : "\(Labels.plural(word, published)) published", icon: "checkmark.circle.fill", tint: .green, filled: true)
                            .help("On lecture.studio: \(r.url)")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: c.course as NSString) }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let dragged = obj as? String, dragged != c.course else { return }
                Task { @MainActor in
                    var order = cards.filter { !isArchived($0) && $0.course != "(root)" }.map(\.course)
                    guard let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: c.course) else { return }
                    order.remove(at: from); order.insert(dragged, at: to)
                    customOrder = order; AppSettings.courseOrder = order
                    if sort != .custom { sort = .custom; AppSettings.courseSort = sort.rawValue }
                }
            }
            return true
        }
        .contextMenu {
            if !root {
                Button("Move earlier") { move(c.course, by: -1) }
                Button("Move later") { move(c.course, by: 1) }
                Divider()
                Button(meta?.archived == true ? "Unarchive" : "Archive") { store.setArchived(c.course, meta?.archived != true) }
                Button("New term from this course…") { store.course = c.course; store.unit = nil; store.dialog = .newTerm }
                Divider()
                Button("Hide from the studio (not a course or a talk)") { store.setExcluded(c.course, true) }
                Button("Remove…", role: .destructive) { store.course = c.course; store.unit = nil; store.dialog = .remove }
            }
        }
    }
}

struct DashedCard: View {
    var icon: String
    var title: String
    var description: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).frame(width: 28, height: 28).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.tertiary))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// The three things a new studio needs, as a checklist that ticks itself.
struct GettingStartedView: View {
    @Environment(StudioStore.self) private var store
    var state: GettingStartedState

    var remaining: Int { [state.profile, state.course, state.sources, state.assistant].filter { !$0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Getting started", systemImage: "sparkles").font(.headline)
                    Text(remaining == 0 ? "Everything is in place. Open a course or a talk and start writing, or ask the assistant for an outline." : "\(remaining) of 4 left. Then open a session and write, or ask the assistant to draft from your sources.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.dismissChecklist() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Hide. The profile button and the cards below stay.")
            }
            step(done: state.profile, title: "Say who is presenting", detail: "Name, contact lines, and how you teach or speak. Title and closing slides come from this.") {
                Button(state.profile ? "Edit profile" : "Set up profile") { store.dialog = .profile }.buttonStyle(state.profile ? .plainBordered : .prominent)
            }
            step(done: state.course, title: "Create a course or a talk", detail: "A course is a folder of numbered sessions; a talk is one deck. Both get a title slide from your profile.") {
                Button("New course") { store.dialog = .lecture }.buttonStyle(state.course ? .plainBordered : .prominent)
                Button("New talk") { store.dialog = .talk }.buttonStyle(.plainBordered)
            }
            step(done: state.assistant, title: "Connect the assistant", detail: "The assistant runs on an Oberik project you own. The guide walks through it with screenshots: create the project, add a model, allow what the assistant may do, copy the project id and key into Settings. Without it the editor, preview and presenter work; the chat and source search do not.") {
                Button("Setup guide") { NSWorkspace.shared.open(oberikGuideURL) }.buttonStyle(.plainBordered)
                SettingsLink { Text(state.assistant ? "Settings" : "Connect…") }.buttonStyle(state.assistant ? .plainBordered : .prominent)
            }
            step(done: state.sources, title: "Add the material the deck should draw on", detail: "Readings, papers, notes, or old slides. They are indexed so the assistant can search and cite them when you ask. Shared sources are searched everywhere; a course or a session can have its own.") {
                Button("Add shared sources") { store.dialog = .sources }.buttonStyle(state.sources ? .plainBordered : .prominent)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    func step<A: View>(done: Bool, title: String, detail: String, @ViewBuilder actions: () -> A) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.accentColor : Color.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                if !done { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack(spacing: 6) { actions() }.controlSize(.small)
        }
    }
}

/// Two button looks the checklist and cards switch between.
enum StudioButtonStyle { case prominent, plainBordered }
extension View {
    @ViewBuilder func buttonStyle(_ s: StudioButtonStyle) -> some View {
        switch s {
        case .prominent: self.buttonStyle(.borderedProminent)
        case .plainBordered: self.buttonStyle(.bordered)
        }
    }
}
