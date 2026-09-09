import SwiftUI
import StudioCore

/// Human-driven git: status, commit all, push, pull. The agent has no git tools.
struct GitBarView: View {
    @Environment(StudioStore.self) private var store
    @State private var st: GitStatus?
    @State private var msg = ""
    @State private var busy: String?
    @State private var open = false

    var git: GitClient? { store.repo.map { GitClient(root: $0.root) } }
    var changed: Int { st?.changes.count ?? 0 }
    var pullReason: String {
        guard let st else { return "" }
        if st.upstream == nil { return "No upstream branch" }
        if changed > 0 { return "Commit first, then pull" }
        return st.behind == 0 ? "Nothing to pull" : ""
    }
    var pushReason: String {
        guard let st else { return "" }
        if st.upstream == nil { return "No upstream branch" }
        if st.ahead == 0 { return changed > 0 ? "Commit first, then push" : "Nothing to push" }
        return ""
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { open.toggle() } label: {
                    HStack(spacing: 4) { Image(systemName: "arrow.triangle.branch"); Text(st?.branch ?? "…").font(.system(.caption, design: .monospaced)); Image(systemName: "chevron.down").font(.caption2).rotationEffect(.degrees(open ? 180 : 0)) }
                }.buttonStyle(.plain).help("Show changed files")
                if let st {
                    Chip(text: "\(changed) changed", tint: changed > 0 ? .accentColor : .secondary, filled: true)
                    if st.ahead > 0 { Chip(text: "\(st.ahead)", icon: "arrow.up") }
                    if st.behind > 0 { Chip(text: "\(st.behind)", icon: "arrow.down") }
                }
                Spacer()
                if st != nil && (!pullReason.isEmpty || !pushReason.isEmpty) {
                    Text(Array(Set([pullReason, pushReason]).filter { !$0.isEmpty }).sorted().joined(separator: ". ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { op("pull") } label: { BusyLabel(busy: busy == "pull", idle: "Pull", working: "Pulling…") }.controlSize(.small).disabled(busy != nil || !pullReason.isEmpty || st == nil).help(pullReason.isEmpty ? "Pull with rebase" : pullReason)
                Button { op("push") } label: { BusyLabel(busy: busy == "push", idle: "Push", working: "Pushing…") }.controlSize(.small).disabled(busy != nil || !pushReason.isEmpty || st == nil).help(pushReason.isEmpty ? "Push to the upstream branch" : pushReason)
            }
            if changed > 0 {
                HStack(spacing: 6) {
                    TextField("What changed?", text: $msg).textFieldStyle(.roundedBorder).controlSize(.small).onSubmit { op("commit") }
                    Button { op("commit") } label: { BusyLabel(busy: busy == "commit", idle: "Commit all", working: "Committing…") }.controlSize(.small).buttonStyle(.borderedProminent).disabled(busy != nil || msg.trimmed.isEmpty)
                }
            }
            if open, let st {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if st.changes.isEmpty {
                            Text("Clean. Last commit \(st.lastCommit.map { "\($0.hash) (\($0.date)) \($0.subject)" } ?? "none")").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(st.changes, id: \.path) { c in
                            HStack(spacing: 6) { Chip(text: c.status.isEmpty ? "?" : c.status); Text(c.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 128)
            }
            if let e = st?.fetchError {
                HStack(spacing: 6) { Image(systemName: "exclamationmark.triangle"); Text("Fetch failed: \(e)").lineLimit(2) }.font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        .overlay(alignment: .top) { Divider() }
        .task { await refresh(fetch: true) }
        .task(id: store.refreshKey) { await refresh(fetch: false) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                await refresh(fetch: true)
            }
        }
    }

    func refresh(fetch: Bool) async {
        guard let git else { return }
        do { st = try await git.status(fetchFirst: fetch) } catch { store.toasts.error("Git status failed", error) }
    }

    func op(_ kind: String) {
        guard let git, busy == nil else { return }
        busy = kind
        Task {
            do {
                switch kind {
                case "commit":
                    let r = try await git.commitAll(msg)
                    store.toasts.success("Committed \(r.hash)", "\(r.files) file\(r.files == 1 ? "" : "s")")
                    msg = ""
                case "push":
                    store.toasts.success("Pushed", try await git.push())
                default:
                    store.toasts.success("Pulled", try await git.pull())
                    await store.refreshFiles()
                    if !store.filePath.isEmpty && !store.dirty { await store.openFile(store.filePath, select: false) }
                }
                await refresh(fetch: kind != "commit")
            } catch {
                store.toasts.error("\(kind.capFirst) failed", error)
            }
            busy = nil
        }
    }
}
