import SwiftUI
import AppKit
import StudioCore

/// Publish the open course to lecture.studio: the plan (decks, PDFs, assets, themes, the syllabus), what
/// is already there, the run with its progress, and the course page at the end.
struct PublishSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var plan: PublishPlan?
    @State private var remote: [String: PlatformClient.RemoteFile] = [:]
    @State private var existing: PlatformClient.Course?
    @State private var handle = ""
    @State private var visibility = "private"
    @State private var progress = (done: 0, total: 0, current: "")
    @State private var uploaded = 0
    @State private var skipped = 0
    @State private var courseURL: URL?
    @State private var publishTask: Task<Void, Never>?

    enum Phase: Equatable { case loading, noToken, review, publishing, done, failed(String) }

    var client: PlatformClient? {
        let token = AppSettings.platformToken.trimmed
        guard !token.isEmpty, let origin = URL(string: AppSettings.platformOrigin) else { return nil }
        return PlatformClient(origin: origin, token: token)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Publish \(Labels.courseLabel(store.course, store.meta))", icon: "arrow.up.circle", description: "Sends the decks as Marp Markdown with their themes and images, the exported PDFs and the syllabus to your page on lecture.studio. Students see each \(plan?.unitLabel.lowercased() ?? "week") from its lecture date. Instructor guides and solutions never leave this Mac.")
            switch phase {
            case .loading: HStack { ProgressView().controlSize(.small); Text("Reading the course and your page…").foregroundStyle(.secondary) }
            case .noToken: noTokenBody
            case .review: reviewBody
            case .publishing: publishingBody
            case .done: doneBody
            case .failed(let m): failedBody(m)
            }
        }
        .dialogFrame(width: 620)
        .interactiveDismissDisabled(phase == .publishing)
        .task { await load() }
    }

    // MARK: states

    @ViewBuilder var noTokenBody: some View {
        Text("Publishing needs a personal token from your lecture.studio account. Create one on the website (Settings › Mac app), then paste it in this app's Settings › Publish.").fixedSize(horizontal: false, vertical: true)
        HStack {
            Button { NSWorkspace.shared.open(URL(string: AppSettings.platformOrigin + "/settings#mac")!) } label: { Label("Create a token on lecture.studio", systemImage: "safari") }
            SettingsLink { Label("Open Settings", systemImage: "gear") }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder var reviewBody: some View {
        if let plan {
            let units = Dictionary(grouping: plan.items, by: { $0.unit })
            LabeledField(label: "Course on lecture.studio", hint: existing.map { "Exists: \($0.url). Its visibility stays as set on the website." } ?? "New: lecture.studio/@\(handle)/\(plan.slug). \(plan.startDate.map { "First lecture \($0), \(plan.weekCount) \(plan.unitLabel.lowercased())s" } ?? "No first-lecture date in the course settings, so no \(plan.unitLabel.lowercased()) opens by itself until you set one on the website.")") {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(units.keys.sorted { ($0 ?? 0) < ($1 ?? 0) }, id: \.self) { unit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unit.map { "\(plan.unitLabel) \($0)\(plan.topics[$0].map { ": \($0)" } ?? "")" } ?? "Course files").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(units[unit] ?? []) { item in itemRow(item) }
                        }
                    }
                    if !plan.heldBack.isEmpty {
                        Text("Held back (instructor material): \(plan.heldBack.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: 340)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                let toSend = plan.items.filter { $0.selected && !isUpToDate($0) }
                Text(toSend.isEmpty ? "Everything selected is already up to date." : "\(toSend.count) file\(toSend.count == 1 ? "" : "s") to send, \(ByteCountFormatter.string(fromByteCount: Int64(toSend.reduce(0) { $0 + $1.size }), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { publish() } label: { Label(existing == nil ? "Create and publish" : "Publish", systemImage: "arrow.up.circle") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(plan.items.allSatisfy { !$0.selected })
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
            Text("Sending \(progress.done + 1) of \(progress.total): \(progress.current)").font(.callout)
        }
        HStack { Spacer(); Button("Cancel") { publishTask?.cancel() } }
    }

    @ViewBuilder var doneBody: some View {
        Label("Published. \(uploaded) file\(uploaded == 1 ? "" : "s") sent\(skipped > 0 ? ", \(skipped) already up to date" : "").", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        Text("Students who have the join link see the \(plan?.unitLabel.lowercased() ?? "week")s that have reached their date. Visibility, the join link and the roster are on the course page.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    func key(_ item: PublishItem) -> String { "\(item.unit ?? 0)/\(item.path)" }
    func isUpToDate(_ item: PublishItem) -> Bool {
        guard let r = remote[key(item)] else { return false }
        return r.size == item.size && (hashes[key(item)].map { $0 == r.sha256 } ?? true)
    }
    @State private var hashes: [String: String] = [:]

    func setSelected(_ item: PublishItem, _ v: Bool) {
        guard var p = plan, let i = p.items.firstIndex(where: { $0.id == item.id }) else { return }
        p.items[i].selected = v
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
        let p = Publish.plan(fs: fs, course: course, meta: meta, courseMeta: cm, themeDirs: [WebHost.resource("themes")])
        plan = p
        do {
            let me = try await client.me()
            handle = me.handle
            existing = me.courses.first { $0.slug == p.slug }
            if existing != nil {
                let files = try await client.files(p.slug)
                remote = Dictionary(uniqueKeysWithValues: files.map { ("\($0.week ?? 0)/\($0.path)", $0) })
                // Hash the local files that exist remotely with the same size, to tell "changed" from "up to date".
                var h: [String: String] = [:]
                for item in p.items where remote[key(item)]?.size == item.size {
                    if let d = try? data(for: item) { h[key(item)] = PlatformClient.sha256(d) }
                }
                hashes = h
            }
            phase = .review
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_PUBLISH"] == "run" { publish() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func publish() {
        guard let client, let p = plan else { return }
        let items = p.items.filter { $0.selected && !isUpToDate($0) }
        skipped = p.items.filter { $0.selected && isUpToDate($0) }.count
        progress = (0, items.count, "")
        uploaded = 0
        phase = .publishing
        publishTask = Task {
            do {
                let ensured = try await client.ensure(PlatformClient.Ensure(slug: p.slug, code: p.code, title: p.title, term: p.term, description: nil, start_date: p.startDate, week_count: p.weekCount, cancelled_dates: p.cancelledDates, visibility: existing == nil ? visibility : nil, unit_label: p.unitLabel))
                courseURL = URL(string: ensured.url)
                for item in items {
                    try Task.checkCancellation()
                    progress.current = item.path
                    let d = try data(for: item)
                    _ = try await client.upload(p.slug, week: item.unit, path: item.path, name: (item.path as NSString).lastPathComponent, data: d, topic: item.unit.flatMap { p.topics[$0] })
                    uploaded += 1
                    progress.done += 1
                }
                // Topics for units that got no upload this time still reach the page.
                for (n, topic) in p.topics where items.contains(where: { $0.unit == n }) == false && !topic.isEmpty {
                    try? await client.setWeek(p.slug, n, topic: topic)
                }
                phase = .done
                store.toasts.show(.success, "Published to lecture.studio", "\(uploaded) file\(uploaded == 1 ? "" : "s") sent.")
            } catch is CancellationError {
                phase = .failed("Publishing was cancelled after \(uploaded) file\(uploaded == 1 ? "" : "s"). What was sent stays; run it again to finish.")
            } catch {
                phase = .failed("\(error.localizedDescription) \(uploaded > 0 ? "(\(uploaded) file\(uploaded == 1 ? "" : "s") were sent before that.)" : "")")
            }
        }
    }
}
