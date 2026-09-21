import SwiftUI
import AppKit
import StudioCore

/// Publish the open course (or one unit of it) to lecture.studio: the plan, what is already there, missing
/// PDFs exported on the way, the run with its progress, then the join link and visibility of the course page.
struct PublishSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var plan: PublishPlan?
    @State private var remote: [String: PlatformClient.RemoteFile] = [:]
    @State private var existing: PlatformClient.Course?
    @State private var details: PlatformClient.CourseDetails?
    @State private var handle = ""
    @State private var visibility = "private"
    @State private var progress = (done: 0, total: 0, current: "")
    @State private var uploaded = 0
    @State private var skipped = 0
    @State private var exported = 0
    @State private var exportFailures: [String] = []
    @State private var exportMissing = true
    @State private var courseURL: URL?
    @State private var publishTask: Task<Void, Never>?
    @State private var hashes: [String: String] = [:]
    @State private var copied = false
    @State private var settingsBusy = false

    enum Phase: Equatable { case loading, noToken, review, publishing, done, failed(String) }

    var unit: Int? { store.publishUnit }

    var client: PlatformClient? {
        let token = AppSettings.platformToken.trimmed
        guard !token.isEmpty, let origin = URL(string: AppSettings.platformOrigin) else { return nil }
        return PlatformClient(origin: origin, token: token)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: unit.map { "Publish \(plan?.unitLabel ?? "Week") \($0) of \(Labels.courseLabel(store.course, store.meta))" } ?? "Publish \(Labels.courseLabel(store.course, store.meta))", icon: "arrow.up.circle", description: "Sends PDFs to your page on lecture.studio: the PDF exported from each \(plan?.unitLabel.lowercased() ?? "week")'s deck, and any other PDF you tick. Decks, images and themes stay on this Mac. Students see each \(plan?.unitLabel.lowercased() ?? "week") from its lecture date. Instructor guides and solutions never leave this Mac.")
            switch phase {
            case .loading: HStack { ProgressView().controlSize(.small); Text("Reading the course and your page…").foregroundStyle(.secondary) }
            case .noToken: noTokenBody
            case .review: reviewBody
            case .publishing: publishingBody
            case .done: doneBody
            case .failed(let m): failedBody(m)
            }
        }
        .dialogFrame(width: 640)
        .interactiveDismissDisabled(phase == .publishing)
        .task { await load() }
        .onDisappear { store.publishUnit = nil }
    }

    // MARK: states

    @ViewBuilder var noTokenBody: some View {
        Text("Publishing needs this Mac connected to your lecture.studio account. Press Connect: the website signs you in and hands the app a token. No copying.").fixedSize(horizontal: false, vertical: true)
        HStack {
            Button { store.connectPlatform() } label: { Label("Connect lecture.studio", systemImage: "link") }.buttonStyle(.borderedProminent)
            SettingsLink { Label("Settings", systemImage: "gear") }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .onChange(of: store.platformHandle) { _, h in if h != nil { phase = .loading; Task { await load() } } }
    }

    @ViewBuilder var reviewBody: some View {
        if let plan {
            let units = Dictionary(grouping: plan.items, by: { $0.unit })
            LabeledField(label: "Course on lecture.studio", hint: existing.map { "Exists: \($0.url). Visibility and the join link are shown after publishing." } ?? "New: lecture.studio/@\(handle)/\(plan.slug). \(plan.startDate.map { "First lecture \($0), \(plan.weekCount) \(plan.unitLabel.lowercased())s" } ?? "No first-lecture date in the course settings, so no \(plan.unitLabel.lowercased()) opens by itself until you set one on the website.")") {
                HStack {
                    Text("\(plan.code.map { "\($0) · " } ?? "")\(plan.title)\(plan.term.map { " · \($0)" } ?? "")").font(.body.weight(.medium))
                    Spacer()
                    if existing == nil {
                        Picker("", selection: $visibility) {
                            Text("Private (join link)").tag("private")
                            Text("Listed, invite only").tag("listed")
                            Text("Public").tag("public")
                        }.labelsHidden().frame(width: 190)
                    }
                }
            }
            HStack(spacing: 6) {
                Text("PDFs to send").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Select all") { selectAll(true) }.help("Tick every PDF")
                Button("Deselect all") { selectAll(false) }.help("Untick every PDF")
                Button("Deck PDFs only") { selectDeckPdfs() }.help("Tick only the PDF exported from each \(plan.unitLabel.lowercased())'s deck; other PDFs stay on this Mac")
            }
            .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(units.keys.sorted { ($0 ?? 0) < ($1 ?? 0) }, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.map { "\(plan.unitLabel) \($0)\(plan.topics[$0].map { ": \($0)" } ?? "")" } ?? "Course files").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(units[u] ?? []) { item in itemRow(item) }
                        }
                    }
                    if plan.items.isEmpty {
                        Text(plan.decks.isEmpty ? "No PDFs in this course yet." : "No PDFs yet: tick the export below, or export the decks first (⇧⌘E).").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    if !plan.heldBack.isEmpty {
                        Text("Held back (instructor material): \(plan.heldBack.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 320)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            let missing = plan.unitsMissingPdf
            if !missing.isEmpty {
                Toggle(isOn: $exportMissing) {
                    Text(store.exporter.status.tool != nil
                         ? "Export the missing PDFs with marp-cli first, into each \(plan.unitLabel.lowercased())'s folder (\(plan.unitLabel.lowercased())\(missing.count == 1 ? "" : "s") \(missing.map(String.init).joined(separator: ", ")))"
                         : "Export the missing PDFs first (\(missing.count)): marp-cli was not found, see Settings › Export")
                        .fixedSize(horizontal: false, vertical: true)
                }.disabled(store.exporter.status.tool == nil)
            }
            HStack {
                let toSend = plan.items.filter { $0.selected && !isUpToDate($0) }
                Text(toSend.isEmpty ? "Everything selected is already up to date." : "\(toSend.count) file\(toSend.count == 1 ? "" : "s") to send, \(ByteCountFormatter.string(fromByteCount: Int64(toSend.reduce(0) { $0 + $1.size }), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { publish() } label: { Label(existing == nil ? "Create and publish" : "Publish", systemImage: "arrow.up.circle") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(plan.items.allSatisfy { !$0.selected } && !(exportMissing && store.exporter.status.tool != nil && !missing.isEmpty))
            }
        }
    }

    func itemRow(_ item: PublishItem) -> some View {
        let up = isUpToDate(item)
        return Toggle(isOn: Binding(get: { item.selected }, set: { v in setSelected(item, v) })) {
            HStack(spacing: 8) {
                Image(systemName: icon(item.kind)).foregroundStyle(.secondary).frame(width: 16)
                Text(item.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                if item.size > Publish.maxBytes { Text("over 40 MB").font(.caption2).foregroundStyle(.red) }
                else if up { Text("up to date").font(.caption2).foregroundStyle(.secondary) }
                else if remote[key(item)] != nil { Text("changed").font(.caption2).foregroundStyle(.orange) }
                else { Text("new").font(.caption2).foregroundStyle(.blue) }
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.caption2).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(item.size > Publish.maxBytes)
    }

    @ViewBuilder var publishingBody: some View {
        ProgressView(value: Double(progress.done), total: Double(max(1, progress.total))) {
            Text(progress.current).font(.callout)
        }
        HStack { Spacer(); Button("Cancel") { publishTask?.cancel() } }
    }

    @ViewBuilder var doneBody: some View {
        Label("Published. \(uploaded) file\(uploaded == 1 ? "" : "s") sent\(skipped > 0 ? ", \(skipped) already up to date" : "")\(exported > 0 ? ", \(exported) PDF\(exported == 1 ? "" : "s") exported" : "").", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        if !exportFailures.isEmpty { Text("Not exported: \(exportFailures.joined(separator: "; "))").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        if let d = details {
            LabeledField(label: "Who can see it") {
                HStack {
                    Picker("", selection: Binding(get: { d.visibility }, set: { v in setVisibility(v) })) {
                        Text("Private (join link)").tag("private")
                        Text("Listed, invite only").tag("listed")
                        Text("Public").tag("public")
                    }.labelsHidden().frame(width: 190).disabled(settingsBusy)
                    Text("\(d.students) student\(d.students == 1 ? "" : "s") enrolled").font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledField(label: "Join link", hint: d.visibility == "public" ? "The course is public; the link still puts a student on the roster." : "Share it with the class. Anyone with the link can join until you rotate it.") {
                HStack {
                    TextField("", text: .constant(d.join_url ?? "No join link yet")).font(.system(.body, design: .monospaced)).disabled(true)
                    if let link = d.join_url {
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string); copied = true } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    }
                    Button { rotate() } label: { BusyLabel(busy: settingsBusy, idle: d.join_url == nil ? "Create" : "Rotate", working: "…") }.disabled(settingsBusy)
                }
            }
        }
        HStack {
            if let courseURL { Button { NSWorkspace.shared.open(courseURL) } label: { Label("Open the course page", systemImage: "safari") } }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder func failedBody(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Try again") { phase = .loading; Task { await load() } }.keyboardShortcut(.defaultAction)
        }
    }

    // MARK: work

    func icon(_ k: PublishKind) -> String {
        switch k { case .deck: "rectangle.on.rectangle"; case .pdf: "doc.richtext"; case .asset: "photo"; case .theme: "paintpalette"; case .doc: "doc.text" }
    }
    func key(_ item: PublishItem) -> String { item.id }
    func isUpToDate(_ item: PublishItem) -> Bool {
        guard let r = remote[key(item)] else { return false }
        return r.size == item.size && (hashes[key(item)].map { $0 == r.sha256 } ?? true)
    }
    func setSelected(_ item: PublishItem, _ v: Bool) {
        guard var p = plan, let i = p.items.firstIndex(where: { $0.id == item.id }) else { return }
        p.items[i].selected = v
        plan = p
    }
    /// Files over the size limit never get ticked.
    func selectAll(_ v: Bool) {
        guard var p = plan else { return }
        for i in p.items.indices { p.items[i].selected = v && p.items[i].size <= Publish.maxBytes }
        plan = p
    }
    func selectDeckPdfs() {
        guard var p = plan else { return }
        for i in p.items.indices { p.items[i].selected = p.isDeckPdf(p.items[i]) && p.items[i].size <= Publish.maxBytes }
        plan = p
    }

    func data(for item: PublishItem) throws -> Data {
        switch item.source {
        case .repo(let rel): return try store.repo!.readBytes(rel)
        case .file(let url): return try Data(contentsOf: url)
        }
    }

    func load() async {
        guard let client else { phase = .noToken; return }
        guard let fs = store.repo, let meta = store.meta else { phase = .failed("Open a course first."); return }
        let course = store.course
        let cm = courseMeta(fs: fs, course: course)
        var p = Publish.plan(fs: fs, course: course, meta: meta, courseMeta: cm, themeDirs: [WebHost.resource("themes")])
        if let unit {
            // One unit: its PDFs; everything else stays out of the way.
            p.items = p.items.filter { $0.unit == unit }
            p.decks = p.decks.filter { $0.key == unit }
        }
        plan = p
        do {
            let me = try await client.me()
            handle = me.handle
            existing = me.courses.first { $0.slug == p.slug }
            if existing != nil {
                let files = try await client.files(p.slug)
                remote = Dictionary(uniqueKeysWithValues: files.map { ("\($0.week ?? 0)/\($0.path)", $0) })
                var h: [String: String] = [:]
                for item in p.items where remote[key(item)]?.size == item.size {
                    if let d = try? data(for: item) { h[key(item)] = PlatformClient.sha256(d) }
                }
                hashes = h
            }
            phase = .review
            await store.exporter.probe()
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_PUBLISH"] == "run" { publish() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func publish() {
        guard let client, var p = plan, let fs = store.repo else { return }
        skipped = p.items.filter { $0.selected && isUpToDate($0) }.count
        uploaded = 0; exported = 0; exportFailures = []
        let toExport = exportMissing && store.exporter.status.tool != nil ? p.unitsMissingPdf : []
        progress = (0, p.items.filter { $0.selected && !isUpToDate($0) }.count + toExport.count, "Starting…")
        phase = .publishing
        let course = store.course
        publishTask = Task {
            do {
                let ensured = try await client.ensure(PlatformClient.Ensure(slug: p.slug, code: p.code, title: p.title, term: p.term, description: nil, start_date: p.startDate, week_count: p.weekCount, cancelled_dates: p.cancelledDates, visibility: existing == nil ? visibility : nil, unit_label: p.unitLabel))
                courseURL = URL(string: ensured.url)
                // Missing PDFs first, into the unit folder next to the deck, so students get them too.
                for u in toExport {
                    try Task.checkCancellation()
                    guard let rel = p.decks[u] else { continue }
                    progress.current = "Exporting \(p.unitLabel.lowercased()) \(u) to PDF…"
                    let deckURL = try fs.resolve(rel)
                    let pdfRel = (rel as NSString).deletingPathExtension + ".pdf"
                    let out = try fs.resolve(pdfRel)
                    var opts = AppSettings.exportOptions; opts.format = .pdf
                    switch await store.exporter.export(deck: deckURL, output: out, options: opts) {
                    case .success:
                        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                        p.items.append(PublishItem(unit: u, path: (pdfRel as NSString).lastPathComponent, source: .repo(pdfRel), kind: .pdf, size: size, selected: true))
                        exported += 1
                    case .failure(let e): exportFailures.append("\(p.unitLabel.lowercased()) \(u): \(e.localizedDescription)")
                    }
                    progress.done += 1
                }
                plan = p
                let items = p.items.filter { $0.selected && !isUpToDate($0) }
                progress.total = progress.done + items.count
                var sent: [String: String] = [:]
                for item in items {
                    try Task.checkCancellation()
                    progress.current = "Sending \(progress.done + 1) of \(progress.total): \(item.path)"
                    let d = try data(for: item)
                    let r = try await client.upload(p.slug, week: item.unit, path: item.path, name: (item.path as NSString).lastPathComponent, data: d, topic: item.unit.flatMap { p.topics[$0] })
                    sent[item.id] = r.sha256
                    uploaded += 1
                    progress.done += 1
                }
                for (n, topic) in p.topics where unit == nil && items.contains(where: { $0.unit == n }) == false && !topic.isEmpty {
                    try? await client.setWeek(p.slug, n, topic: topic)
                }
                // The record: what the page has now, for the course screen's published/changed marks.
                // A record from another account is not this page's: start over.
                var record = PublishRecord.read(fs: fs, course: course).flatMap { $0.belongs(to: handle) ? $0 : nil } ?? PublishRecord(handle: handle, slug: p.slug, url: ensured.url, at: "", files: [:])
                record.handle = handle; record.slug = p.slug; record.url = ensured.url; record.at = ISO8601DateFormatter().string(from: Date())
                for item in p.items where item.selected { if let s = sent[item.id] ?? hashes[item.id] ?? remote[item.id]?.sha256 { record.files[item.id] = s } }
                try? record.write(fs: fs, course: course)
                details = try? await client.course(p.slug)
                phase = .done
                store.toasts.show(.success, "Published to lecture.studio", "\(uploaded) file\(uploaded == 1 ? "" : "s") sent.")
                await store.refreshFiles()
                store.refreshPublishState()
            } catch is CancellationError {
                phase = .failed("Publishing was cancelled after \(uploaded) file\(uploaded == 1 ? "" : "s"). What was sent stays; run it again to finish.")
            } catch {
                phase = .failed("\(error.localizedDescription) \(uploaded > 0 ? "(\(uploaded) file\(uploaded == 1 ? "" : "s") were sent before that.)" : "")")
            }
        }
    }

    func setVisibility(_ v: String) {
        guard let client, let p = plan else { return }
        settingsBusy = true
        Task {
            do { details = try await client.settings(p.slug, PlatformClient.SettingsPatch(visibility: v, joins_locked: nil, rotate_join_link: nil)) }
            catch { store.toasts.show(.error, "Could not change the visibility", error.localizedDescription) }
            settingsBusy = false
        }
    }

    func rotate() {
        guard let client, let p = plan else { return }
        settingsBusy = true; copied = false
        Task {
            do { details = try await client.settings(p.slug, PlatformClient.SettingsPatch(visibility: nil, joins_locked: nil, rotate_join_link: true)) }
            catch { store.toasts.show(.error, "Could not rotate the join link", error.localizedDescription) }
            settingsBusy = false
        }
    }
}
