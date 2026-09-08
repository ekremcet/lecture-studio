import SwiftUI
import AppKit
import StudioCore

/// The source materials the agent may search: root `sources/`, the lecture's, the unit's. Mirrors SourcesDialog.tsx.
struct SourcesSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SourceRow] = []
    @State private var loaded = false
    @State private var indexError: String?
    @State private var busy: String?
    @State private var removing: SourceRow?
    @State private var addingUrl: SourceScope?
    @State private var expandedGroups: Set<String> = []
    @State private var removingGroup: SourceGroup?

    var course: String { store.course == "(root)" ? "" : store.course }
    var unit: String { store.unit ?? "" }
    var isRoot: Bool { course.isEmpty }
    var showUnit: Bool { !store.talk && store.stage == .work }

    var sections: [(scope: SourceScope, title: String, disabled: Bool)] {
        var s: [(SourceScope, String, Bool)] = [(.global, "Every lecture and talk", false)]
        if !isRoot { s.append((.lecture, "This lecture: \(Labels.courseLabel(course))", false)) }
        if showUnit && !isRoot { s.append((.unit, unit.isEmpty ? "This unit" : "This unit: \(Labels.unitLabel(unit))", unit.isEmpty)) }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeader(title: "Source materials", icon: "book", description: "Material you and the assistant can read, search, and cite. Files live in the repository under sources/ folders and are indexed for retrieval. Files you copy into those folders by hand show up here with an Index button.")
            if let e = indexError { Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sections, id: \.scope) { s in section(s.scope, s.title, s.disabled) }
                }
            }
            .frame(minHeight: 200, maxHeight: 520)
            HStack {
                Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(.secondary).controlSize(.small)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .dialogFrame(width: 680)
        .task { await refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if rows.contains(where: { $0.doc != nil && $0.doc!.status != "ready" && $0.doc!.status != "failed" }) { await refresh() }
            }
        }
        .sheet(item: $addingUrl) { sc in
            AddUrlSheet(scope: sc, course: course, unit: unit, tags: { path in tagsFor(sc, path) }, onDone: { Task { await refresh() } })
        }
        .confirmationDialog("Remove this source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { r in
            Button("Remove", role: .destructive) { remove(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text("\(r.name) is removed from the index and deleted from the repository. Use git to bring it back.") }
        .confirmationDialog("Remove this set?", isPresented: Binding(get: { removingGroup != nil }, set: { if !$0 { removingGroup = nil } }), presenting: removingGroup) { g in
            Button("Remove \(g.members.count) files", role: .destructive) { removeAll(g.members) }
            Button("Cancel", role: .cancel) {}
        } message: { g in Text("\(g.title) and the \(g.members.count) files fetched with it are removed from the index and deleted from the repository.") }
    }

    func refresh() async {
        let (r, e) = await store.sourceRows(course: course, unit: store.stage == .work ? unit : nil)
        rows = r
        indexError = e
        loaded = true
    }

    func section(_ scope: SourceScope, _ title: String, _ disabled: Bool) -> some View {
        let list = rows.filter { $0.scope == scope }
        let pending = list.filter(\.pending)
        let icon = scope == .global ? "globe" : scope == .lecture ? "graduationcap" : "calendar"
        let hint = scope == .global ? "Searched in every conversation. Folder: sources/ at the repo root." : scope == .lecture ? "Searched in every conversation of this lecture. Folder: <lecture>/sources/." : "Searched only when this unit is open. Folder: <lecture>/<unit>/sources/."
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.callout.weight(.medium)).lineLimit(1).help(hint)
                Spacer()
                if pending.count > 1 {
                    Button { index(pending, key: "index-\(scope.rawValue)") } label: { BusyLabel(busy: busy == "index-\(scope.rawValue)", idle: "Index \(pending.count) files", working: "Indexing…") }.controlSize(.small).disabled(busy != nil)
                }
                Button { addingUrl = scope } label: { Label("Add URL", systemImage: "link") }.controlSize(.small).disabled(disabled || busy != nil)
                Button { pick(scope) } label: { BusyLabel(busy: busy == scope.rawValue, idle: "Add files", working: "Uploading…") }.controlSize(.small).disabled(disabled || busy == scope.rawValue)
            }
            if list.isEmpty {
                VStack(spacing: 4) {
                    if !loaded { ProgressView().controlSize(.small) } else { Image(systemName: "doc.text").foregroundStyle(.secondary) }
                    Text(disabled ? "Open a unit to add its sources" : !loaded ? "Loading…" : "No sources yet").font(.callout)
                    if loaded && !disabled { Text("Add readings, papers, notes, or slides; the agent searches and cites them.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(SourceGroup.group(list).enumerated()), id: \.element.id) { i, g in
                        if i > 0 { Divider() }
                        if g.members.count == 1 {
                            row(g.members[0])
                        } else {
                            groupRow(g)
                            if expandedGroups.contains(g.id) {
                                ForEach(g.members) { r in Divider(); row(r).padding(.leading, 22) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    /// One line for a reference course and everything fetched with it; open it to see the files.
    func groupRow(_ g: SourceGroup) -> some View {
        let open = expandedGroups.contains(g.id)
        return HStack(spacing: 8) {
            Button { if open { expandedGroups.remove(g.id) } else { expandedGroups.insert(g.id) } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption2).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).frame(width: 10)
                    Image(systemName: "link").foregroundStyle(.secondary)
                    Text(g.title).font(.callout).lineLimit(1)
                    Text("\(g.members.count) files").font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the files" : "Show the files")
            Spacer()
            if g.pending > 0 {
                Button { index(g.members.filter(\.pending), key: "index-" + g.id) } label: { BusyLabel(busy: busy == "index-" + g.id, idle: "Index \(g.pending)", working: "Indexing…") }.controlSize(.small).disabled(busy != nil)
            } else if g.failed > 0 {
                Chip(text: "\(g.failed) failed", tint: .red, filled: true)
            } else if g.ready == g.members.count {
                Chip(text: "ready", tint: .green, filled: true)
            } else {
                Chip(text: "indexing \(g.ready)/\(g.members.count)")
            }
            Button { removingGroup = g } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(busy != nil).help("Remove the whole set")
        }
        .padding(.vertical, 5)
    }

    func row(_ r: SourceRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(r.name).font(.callout).lineLimit(1).help(r.path ?? r.name)
            Spacer()
            if r.pending {
                Button { index([r], key: r.key) } label: { BusyLabel(busy: busy == r.key, idle: "Index", working: "Indexing…") }.controlSize(.small).disabled(busy != nil).help("This file is in the repository but not indexed for the agent yet.")
            } else if r.doc?.status == "failed" {
                Chip(text: "failed", tint: .red, filled: true)
                Button { retry(r) } label: { BusyLabel(busy: busy == r.key, idle: "Retry", working: "Retrying…") }.controlSize(.small).disabled(busy != nil).help("Ask the index to process this file again.")
            } else {
                Chip(text: r.doc?.status ?? "indexed", tint: r.doc?.status == "ready" ? .green : .secondary, filled: r.doc?.status == "ready")
            }
            Button { removing = r } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(busy == r.key).help("Remove")
        }
        .padding(.vertical, 5)
    }

    func tagsFor(_ scope: SourceScope, _ path: String) -> [String] {
        let t = sourceTags(course: course, unit: unit)
        let base = scope == .global ? [t.global] : scope == .lecture ? [t.lecture] : [t.lecture, t.week]
        return base + ["path:\(path)"]
    }

    func pick(_ scope: SourceScope) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.message = "Add source files"
        guard p.runModal() == .OK, !p.urls.isEmpty, let fs = store.repo else { return }
        busy = scope.rawValue
        Task {
            do {
                for u in p.urls {
                    let data = try Data(contentsOf: u)
                    let saved = try SourceFolders.store(fs: fs, course: scope == .global ? "" : course, unit: scope == .unit ? unit : "", fileName: u.lastPathComponent, data: data)
                    try await store.agent.uploadDocument(repoPath: saved, name: u.lastPathComponent, tags: tagsFor(scope, saved))
                    store.toasts.success("Source added", "\(u.lastPathComponent), indexing")
                }
                await store.refreshFiles()
                await refresh()
            } catch { store.toasts.error("Upload failed", error) }
            busy = nil
        }
    }

    func index(_ list: [SourceRow], key: String) {
        busy = key
        Task {
            do {
                for r in list {
                    guard let path = r.path else { continue }
                    try await store.agent.uploadDocument(repoPath: path, name: r.name, tags: tagsFor(r.scope, path))
                    store.toasts.success("Indexing", r.name)
                }
                await store.refreshFiles()
                await refresh()
            } catch { store.toasts.error("Could not index the file", error) }
            busy = nil
        }
    }

    func retry(_ r: SourceRow) {
        guard let d = r.doc else { return }
        busy = r.key
        Task {
            do {
                try await store.agent.reingestDocument(d.id)
                store.toasts.success("Indexing again", r.name)
                await refresh()
            } catch { store.toasts.error("Could not re-index the file", error) }
            busy = nil
        }
    }

    func removeAll(_ rows: [SourceRow]) {
        busy = "group"
        Task {
            var failed = 0
            for r in rows {
                do {
                    if let d = r.doc { try await store.agent.deleteDocument(d.id) }
                    if let p = r.path, let fs = store.repo { try? SourceFolders.remove(fs: fs, path: p) }
                } catch { failed += 1 }
            }
            if failed == 0 { store.toasts.success("Removed", "\(rows.count) files") } else { store.toasts.error("Some files could not be removed", "\(failed) of \(rows.count)") }
            await store.refreshFiles()
            await refresh()
            busy = nil
        }
    }

    func remove(_ r: SourceRow) {
        busy = r.key
        Task {
            do {
                if let d = r.doc { try await store.agent.deleteDocument(d.id) }
                if let p = r.path, let fs = store.repo { try? SourceFolders.remove(fs: fs, path: p) }
                store.toasts.success("Source removed", r.name)
                await store.refreshFiles()
                await refresh()
            } catch { store.toasts.error("Could not remove the source", error) }
            busy = nil
        }
    }
}

/// Add a source from a URL: a reference course crawled page by page, one web page, or a document.
struct AddUrlSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var scope: SourceScope
    var course: String
    var unit: String
    var tags: (String) -> [String]
    var onDone: () -> Void
    @State private var urlText = ""
    @State private var kind: UrlSourceKind = .referenceCourse
    @State private var name = ""
    @State private var stayUnder = ""
    @State private var stayUnderEdited = false
    @State private var busy = false
    @State private var progress = ""
    @State private var withDocuments = true

    var url: URL? {
        let t = urlText.trimmed
        guard let u = URL(string: t.contains("://") ? t : "https://" + t), let h = u.host, !h.isEmpty else { return nil }
        return u
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Add from a URL", icon: "link", description: "The content is saved as a file under the sources folder of this scope and indexed like any other source, so the agent can search, cite and read it.")
            LabeledField(label: "URL") {
                TextField("https://example.edu/course/spring2026/schedule/", text: $urlText)
                    .onChange(of: urlText) { _, _ in
                        if let u = url, !stayUnderEdited { stayUnder = WebSources.scope(of: u) }
                        if name.isEmpty || !nameEdited, let u = url { suggestedName = suggest(u) }
                    }
            }
            LabeledField(label: "Type", hint: kind.help) {
                Picker("", selection: $kind) { ForEach(UrlSourceKind.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().pickerStyle(.segmented)
            }
            if kind == .referenceCourse {
                LabeledField(label: "Stay under", hint: "Only pages whose address starts with this are fetched (same site). Up to \(WebSources.maxPages) pages, \(WebSources.maxDepth) links deep.") {
                    TextField("host/path/", text: $stayUnder).font(.system(.body, design: .monospaced)).onChange(of: stayUnder) { _, _ in stayUnderEdited = true }
                }
                Toggle("Also download the documents the pages link to (lecture PDFs and the like, same site, up to \(WebSources.maxDocuments))", isOn: $withDocuments)
            }
            LabeledField(label: "Name", hint: "File name in the sources folder.") {
                TextField(suggestedName.isEmpty ? "reference-course" : suggestedName, text: $name).onChange(of: name) { _, v in nameEdited = !v.isEmpty }
            }
            if !progress.isEmpty { Label(progress, systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button { submit() } label: { BusyLabel(busy: busy, idle: "Add and index", working: "Fetching…") }.buttonStyle(.borderedProminent).disabled(busy || url == nil).keyboardShortcut(.defaultAction)
            }
        }
        .dialogFrame(width: 560)
    }

    @State private var suggestedName = ""
    @State private var nameEdited = false

    func suggest(_ u: URL) -> String {
        let parts = u.path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "index.html" }
        let tail = parts.suffix(2).joined(separator: "-")
        return slug(((u.host ?? "").replacingOccurrences(of: "www.", with: "") + "-" + tail))
    }

    func submit() {
        guard let fs = store.repo, let u = url else { return }
        busy = true
        let (k, n, c, un, sp, wd) = (kind, name.isEmpty ? suggestedName : name, scope == .global ? "" : course, scope == .unit ? unit : "", kind == .referenceCourse ? stayUnder : nil, withDocuments)
        let tagsFor = tags
        Task {
            do {
                let paths = try await WebSources.store(fs: fs, course: c, unit: un, kind: k, url: u, name: n, scopePrefix: sp, withDocuments: wd) { p in Task { @MainActor in progress = p } }
                for (i, path) in paths.enumerated() {
                    progress = "Indexing \(i + 1) of \(paths.count)"
                    try await store.agent.uploadDocument(repoPath: path, name: (path as NSString).lastPathComponent, tags: tagsFor(path) + ["url:\(u.absoluteString)"])
                }
                store.toasts.success("Source added", "\(paths.count) file\(paths.count == 1 ? "" : "s"), indexing")
                await store.refreshFiles()
                onDone()
                dismiss()
            } catch { store.toasts.error("Could not add the URL", error) }
            busy = false
        }
    }
}


/// Rows that came from one URL fetch (`name.md` plus `name--file.pdf`) shown as one entry.
struct SourceGroup: Identifiable {
    var id: String
    var title: String
    var members: [SourceRow]
    var pending: Int { members.filter(\.pending).count }
    var failed: Int { members.filter { $0.doc?.status == "failed" }.count }
    var ready: Int { members.filter { $0.doc?.status == "ready" }.count }

    static func key(_ name: String) -> String {
        if let r = name.range(of: "--") { return String(name[..<r.lowerBound]) }
        return (name as NSString).deletingPathExtension
    }

    static func group(_ rows: [SourceRow]) -> [SourceGroup] {
        var order: [String] = []
        var map: [String: [SourceRow]] = [:]
        for r in rows {
            let k = key(r.name)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(r)
        }
        return order.map { k in
            let members = map[k]!
            // Only a set fetched together forms a group: a head file plus its "--" companions.
            let isSet = members.count > 1 && members.contains { $0.name.contains("--") }
            if isSet {
                let head = members.first { !$0.name.contains("--") }
                return SourceGroup(id: k, title: head?.name ?? k, members: members.sorted { a, b in (a.name.contains("--") ? 1 : 0, a.name) < (b.name.contains("--") ? 1 : 0, b.name) })
            }
            return SourceGroup(id: k + "/" + (members.first?.id ?? ""), title: members.first?.name ?? k, members: members.count == 1 ? members : members)
        }.flatMap { g -> [SourceGroup] in
            g.members.count > 1 && !g.members.contains { $0.name.contains("--") } ? g.members.map { SourceGroup(id: $0.id, title: $0.name, members: [$0]) } : [g]
        }
    }
}
