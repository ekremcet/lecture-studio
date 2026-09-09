import SwiftUI
import AppKit
import StudioCore

/// A view over one conversation.
struct ChatView: View {
    @Environment(StudioStore.self) private var store
    var scopes: [ChatScope]
    var defaultKey: String
    @State private var scopeKey = ""
    @State private var input = ""
    @State private var pending: [PendingAttachment] = []
    @State private var dropTarget = false
    @State private var historyOpen = false

    var scope: ChatScope { scopes.first { $0.key == scopeKey } ?? scopes[0] }

    var body: some View {
        let conv = store.conversation(scope.key)
        VStack(spacing: 0) {
            toolbar(conv)
            Divider()
            if !conv.todos.isEmpty { todos(conv) }
            messages(conv)
            Divider()
            composer(conv)
        }
        .onAppear { scopeKey = defaultKey }
        .onChange(of: defaultKey) { _, k in scopeKey = k }
        .sheet(isPresented: Binding(get: { conv.approval != nil }, set: { if !$0 { store.answerApproval(conv, approved: false) } })) {
            if let a = conv.approval { ApprovalSheet(request: a) { store.answerApproval(conv, approved: $0) } }
        }
        .sheet(isPresented: Binding(get: { conv.question != nil }, set: { if !$0 { store.answerQuestion(conv, answer: ["chat_instead": true]) } })) {
            if let q = conv.question { QuestionSheet(pending: q) { store.answerQuestion(conv, answer: $0) } }
        }
        .sheet(item: Binding(get: { store.savingAttachment }, set: { store.savingAttachment = $0 })) { a in SaveAttachmentSheet(attachment: a, defaultDir: store.currentDir) }
    }

    func toolbar(_ conv: Conversation) -> some View {
        HStack(spacing: 6) {
            if scopes.count > 1 {
                Picker("", selection: $scopeKey) { ForEach(scopes) { Text($0.label).tag($0.key) } }.labelsHidden().controlSize(.small).fixedSize().help("Which conversation: this unit or the whole course")
            }
            Text(conv.messages.isEmpty ? "New conversation" : conv.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer()
            Button { historyOpen.toggle() } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                .controlSize(.small).buttonStyle(.plain)
                .disabled(conv.running)
                .help(conv.running ? "Earlier conversations open once this reply has finished" : "Earlier conversations of this \(scopes.count > 1 && scope.key == scopes[0].key ? "unit" : "course")")
                .popover(isPresented: $historyOpen, arrowEdge: .bottom) { ChatHistoryList(scope: scope, current: conv.id) { historyOpen = false } }
            Button { store.resetConversation(scope.key) } label: { Label("New", systemImage: "plus.bubble") }.controlSize(.small).buttonStyle(.plain).help("Start a new conversation (this one stays in the history)")
        }
        .padding(.horizontal, 8).frame(height: 32)
    }

    func short(_ m: String) -> String { m.contains("/") ? String(m.split(separator: "/", maxSplits: 1).last!) : m }
    var defaultLabel: String {
        if let m = store.models, m.tiersMode == "auto" { return "Auto" }
        if let d = store.models?.defaultModel { return "Default (\(short(d)))" }
        return "Default"
    }

    func todos(_ conv: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(conv.todos) { t in
                HStack(spacing: 6) {
                    if t.status == "in_progress" { ProgressView().controlSize(.mini) } else { Image(systemName: "checklist").font(.caption2) }
                    Text(t.content).font(.caption).strikethrough(t.status == "completed").foregroundStyle(t.status == "completed" ? .secondary : .primary)
                }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        .overlay(alignment: .bottom) { Divider() }
    }

    // The transcript is the hot path while a reply streams: every change of the last message
    // re-renders this. Rows are Equatable, so only the streaming row's body and layout run per
    // tick (see MessageRow), and a finished reply is one native text view (RichText), so the
    // display list stays a few items per row. A plain stack, so scrolling to the end is exact: a
    // lazy stack estimated tall rows and cut their ends off. The scroll view keeps the bottom in view
    // while content grows (a reply streams, or changes from plain text to markdown at the end of
    // the turn) as long as the reader is at the bottom; scrolling up stops that, as in any chat.
    func messages(_ conv: Conversation) -> some View {
        let lastId = conv.messages.last?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        if conv.messages.isEmpty { emptyState }
                        ForEach(conv.messages) { m in
                            MessageRow(message: m, streaming: conv.running && m.role == .assistant && m.id == lastId).equatable()
                        }
                    }
                    .padding(12)
                    // The very end of the content, outside the padding: a scroll to it lands exactly at the
                    // edge, which is what the size-change anchor below needs to keep following.
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // A new message: to the end now, and once more after the rows have settled, so the reply
            // that follows grows in view (the size-change anchor holds only from the bottom).
            .onChange(of: conv.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                Task { @MainActor in
                    for wait in [150, 300, 500] { try? await Task.sleep(for: .milliseconds(wait)); proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            // Another conversation (History, New) gets a fresh scroll view that opens at its end: the
            // old one kept its offset from a long transcript and showed nothing of a short one.
            .id(conv.id)
            .task(id: conv.id) {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder var emptyState: some View {
        if !store.oberikConfigured {
            EmptyBlock(icon: "sparkles", title: "Connect the assistant", description: "The assistant runs on an Oberik project you own: outlines, drafts, slide checks and speaker notes from your sources. The guide shows every step with screenshots; then paste the project id and key in Settings. Everything else in the app works without it.") {
                HStack {
                    Button { NSWorkspace.shared.open(oberikGuideURL) } label: { Label("Setup guide", systemImage: "book") }
                    SettingsLink { Label("Connect…", systemImage: "gear") }.buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 12)
        } else {
            connectedEmptyState
        }
    }

    var connectedEmptyState: some View {
        EmptyBlock(icon: "bubble.left", title: "Ask the assistant", description: scope.hint) {
            VStack(spacing: 8) {
                if !scope.emptyActions.isEmpty {
                    FlowRow(spacing: 6, alignment: .center) {
                        ForEach(scope.emptyActions) { a in Button { store.dialog = a.dialog } label: { Label(a.label, systemImage: a.icon) } }
                    }
                }
                FlowRow(spacing: 6, alignment: .center) {
                    ForEach(scope.starters) { s in
                        Button { input = s.prompt } label: { Label(s.label, systemImage: "sparkles") }.controlSize(.small).help(s.prompt)
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    func composer(_ conv: Conversation) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Return adds a line; ⌘↩ sends. The box grows with the text up to about eight lines, then scrolls.
            let lines = input.split(separator: "\n", omittingEmptySubsequences: false).count
            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDisabled(lines <= 8)
                .frame(minHeight: 44, maxHeight: lines <= 8 ? nil : 180)
                .fixedSize(horizontal: false, vertical: lines <= 8)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty { Text(conv.running ? "The assistant is working…" : "Ask for a change… (↩ new line, ⌘↩ sends)").foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false) }
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) { send(); return .handled }
                    return .ignored
                }
            if !pending.isEmpty {
                FlowRow(spacing: 4) {
                    ForEach(pending) { a in
                        HStack(spacing: 4) {
                            Image(systemName: a.isImage ? "photo" : "doc").font(.caption2)
                            Text(a.name).font(.caption).lineLimit(1)
                            Button { pending.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Button { pickFiles() } label: { Image(systemName: "paperclip") }.controlSize(.small).help("Attach files or images (or drop them on the box)")
                Picker("", selection: Binding(get: { store.model }, set: { store.setModel($0) })) {
                    Text(defaultLabel).tag("")
                    ForEach(store.models?.models ?? []) { m in Text(short(m.id)).tag(m.id) }
                }.labelsHidden().controlSize(.small).fixedSize().help("Model for the next message")
                Spacer()
                if conv.running {
                    Button { store.cancelTurn(scope.key) } label: { Label("Stop", systemImage: "stop.fill") }.controlSize(.small).tint(.red).buttonStyle(.borderedProminent)
                } else {
                    Button { send() } label: { Label("Send", systemImage: "paperplane.fill") }.controlSize(.small).buttonStyle(.borderedProminent).disabled(input.trimmed.isEmpty && pending.isEmpty)
                }
            }
        }
        .padding(8)
        .background(dropTarget ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in pending.append(PendingAttachment(url: url)) }
                }
            }
            return true
        }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.message = "Attach files or images to the next message"
        if p.runModal() == .OK { pending += p.urls.map { PendingAttachment(url: $0) } }
    }

    func send() {
        let text = input.trimmed
        guard !text.isEmpty || !pending.isEmpty, !store.conversation(scope.key).running else { return }
        input = ""
        let files = pending
        pending = []
        let s = scope
        Task { await store.sendMessage(scope: s, text: text, attachments: files) }
    }
}

/// One message. Equatable on the message and the streaming flag: SwiftUI skips the body of every
/// row that did not change, which is all but the last one while a reply streams. While streaming
/// the text is one plain `Text` (no markdown, no selection); the block layout, with its nested
/// stacks, appears once the turn ends.
struct MessageRow: View, Equatable {
    var message: ChatMessage
    var streaming: Bool
    @Environment(StudioStore.self) private var store
    @State private var stepsOpen: Bool? = nil

    static func == (a: MessageRow, b: MessageRow) -> Bool { a.message == b.message && a.streaming == b.streaming }

    var body: some View {
        let user = message.role == .user
        VStack(alignment: user ? .trailing : .leading, spacing: 6) {
            if streaming {
                if !message.content.isEmpty { bubble(StreamingText(message.content), user: user) }
            } else if user {
                bubble(Text(message.content).textSelection(.enabled), user: true)
            } else if !message.content.isEmpty {
                // Empty otherwise only when a turn never finished (the app quit mid-reply): no bubble then.
                bubble(RichText(text: message.content), user: false)
            }
            if streaming {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(Activity.describe(message.events)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            if let e = message.error {
                Text(e).font(.caption).padding(8).background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.red)
            }
            if !message.events.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { stepsOpen ?? false }, set: { stepsOpen = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(message.events.enumerated()), id: \.offset) { _, e in Text(e).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.padding(.top, 2)
                } label: { Text("\(message.events.count) steps").font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth: 520, alignment: .leading)
            }
            if !message.citations.isEmpty {
                FlowRow(spacing: 4) {
                    ForEach(Array(message.citations.prefix(8).enumerated()), id: \.offset) { _, c in
                        Chip(text: "\(c.marker.map { "[\($0)] " } ?? "")\(c.label)").help(c.quote ?? "")
                    }
                }.frame(maxWidth: 520, alignment: .leading)
            }
            if !message.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.attachments) { a in
                        HStack(spacing: 8) {
                            if a.isImage, let u = URL(string: a.url) {
                                AsyncImage(url: u) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.secondary.opacity(0.2) }.frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                            } else { Image(systemName: "doc").frame(width: 36, height: 36) }
                            if let u = URL(string: a.url) { Link(a.name ?? a.kind, destination: u).font(.caption) } else { Text(a.name ?? a.kind).font(.caption) }
                            Spacer()
                            if a.isImage { Button { store.savingAttachment = a } label: { Image(systemName: "square.and.arrow.down") }.buttonStyle(.plain).help("Save to assets") }
                        }
                        .padding(6).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    }
                }.frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
    }

    func bubble<V: View>(_ v: V, user: Bool) -> some View {
        v.padding(.horizontal, 12).padding(.vertical, 8)
            .background(user ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(user ? Color.white : Color.primary)
            .frame(maxWidth: 520, alignment: user ? .trailing : .leading)
    }
}

/// The earlier conversations of one scope, newest first. Each course and each unit keeps its own list;
/// the current one is marked, a click shows another, the trash removes one for good.
struct ChatHistoryList: View {
    @Environment(StudioStore.self) private var store
    var scope: ChatScope
    var current: UUID
    var onOpen: () -> Void
    @State private var items: [ChatSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(scope.label).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text("\(items.count) conversation\(items.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if items.isEmpty {
                Text("No conversations yet. The first message starts one; New keeps it here and opens another.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(20).frame(maxWidth: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.id == current ? "bubble.left.fill" : "bubble.left").font(.caption).foregroundStyle(item.id == current ? Color.accentColor : .secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title.isEmpty ? "Untitled" : item.title).lineLimit(1)
                            Text("\(item.updated.formatted(.relative(presentation: .named))) · \(item.messageCount) message\(item.messageCount == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { store.deleteChat(scope.key, id: item.id); items = store.chatHistory(scope.key) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete this conversation")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.openChat(scope.key, id: item.id); onOpen() }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .frame(width: 340)
        .onAppear { items = store.chatHistory(scope.key) }
    }
}

struct ApprovalSheet: View {
    var request: ApprovalRequest
    var resolve: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Allow this action?", description: request.detail ?? "The assistant wants to run an action that needs your approval.")
            VStack(alignment: .leading, spacing: 6) {
                Text(request.summary ?? request.action).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                if let c = request.consequence { Text(c).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("Refuse") { resolve(false) }; Button("Allow") { resolve(true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }
        .dialogFrame()
    }
}

struct QuestionSheet: View {
    var pending: PendingQuestions
    var resolve: ([String: Any]) -> Void
    @State private var selected: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    var complete: Bool { pending.questions.allSatisfy { !(selected[$0.id] ?? []).isEmpty || !(other[$0.id] ?? "").trimmed.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "The assistant has a question", description: "Pick an answer for each item, or close this to reply in the chat instead.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(pending.questions) { q in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(q.header).font(.callout.weight(.medium))
                            Text(q.question).font(.caption).foregroundStyle(.secondary)
                            FlowRow(spacing: 4) {
                                ForEach(q.options, id: \.label) { o in
                                    let on = selected[q.id]?.contains(o.label) ?? false
                                    Button(o.label) {
                                        var s = selected[q.id] ?? []
                                        if q.multi_select { if on { s.remove(o.label) } else { s.insert(o.label) } } else { s = on ? [] : [o.label] }
                                        selected[q.id] = s
                                    }
                                    .buttonStyle(on ? .prominent : .plainBordered).controlSize(.small).help(o.description ?? "")
                                }
                            }
                            if q.allow_other { TextField("Or type your own answer", text: Binding(get: { other[q.id] ?? "" }, set: { other[q.id] = $0 })) }
                        }
                    }
                }
            }
            .frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Reply in chat") { resolve(["chat_instead": true]) }
                Button("Answer") {
                    resolve(["answers": pending.questions.map { q -> [String: Any] in
                        ["question_id": q.id, "selected": Array(selected[q.id] ?? []), "text": (other[q.id] ?? "").trimmed.isEmpty ? NSNull() : (other[q.id] ?? "").trimmed]
                    }])
                }.buttonStyle(.borderedProminent).disabled(!complete)
            }
        }
        .dialogFrame()
    }
}

struct SaveAttachmentSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var attachment: ChatAttachment
    @State var defaultDir: String
    @State private var name = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Save to assets", icon: "photo", description: "The image is stored under the unit's assets/ folder and the markdown to reference it is shown afterwards.")
            LabeledField(label: "Unit folder", hint: "Repo-relative. The file goes into its assets subfolder.") { TextField("course/week3", text: $defaultDir).font(.system(.body, design: .monospaced)) }
            LabeledField(label: "File name") { TextField("diagram.png", text: $name) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button { save() } label: { BusyLabel(busy: busy, idle: "Save", working: "Saving…") }.buttonStyle(.borderedProminent).disabled(busy || defaultDir.trimmed.isEmpty || name.trimmed.isEmpty)
            }
        }
        .dialogFrame()
        .onAppear { name = attachment.name ?? "image.png" }
    }

    func save() {
        busy = true
        Task {
            do {
                let r = try await store.saveAttachment(url: attachment.url, dir: defaultDir, name: name)
                store.toasts.success("Saved \(r.path)", r.markdown)
                dismiss()
            } catch { store.toasts.error("Could not save the image", error) }
            busy = false
        }
    }
}


/// The reply while it streams: plain text in chunks of whole lines, so a flush lays out the last
/// chunk again and the earlier ones keep their size. One `Text` holding the whole reply costs a
/// layout of everything per flush, which grows with the reply (a 30 KB reply took more than a
/// frame per flush).
struct StreamingText: View {
    let text: String
    init(_ text: String) { self.text = text }
    static let linesPerChunk = 24

    var chunks: [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return stride(from: 0, to: lines.count, by: Self.linesPerChunk).map { lines[$0..<min($0 + Self.linesPerChunk, lines.count)].joined(separator: "\n") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, c in
                Text(c)
            }
        }
    }
}

/// One human line for what the agent is doing right now, from the last step it reported. The raw
/// steps stay behind the "N steps" disclosure for whoever wants them.
enum Activity {
    static func describe(_ events: [String]) -> String {
        guard let last = events.last(where: { !$0.hasPrefix("✓") && !$0.hasPrefix("model ") }) else { return "Working…" }
        if last.hasPrefix("thinking") { return "Thinking…" }
        if last.hasPrefix("$ ") { return "Running a command…" }
        guard last.hasPrefix("▶ ") else { return "Working…" }
        let rest = last.dropFirst(2)
        let name = String(rest.split(separator: " ", maxSplits: 1).first ?? "")
        let args = rest.count > name.count ? String(rest.dropFirst(name.count + 1)) : ""
        let path = Rx("\"path\":\"([^\"]+)\"").first(args)?[1] ?? Rx("\"filename\":\"([^\"]+)\"").first(args)?[1] ?? ""
        let file = path.split(separator: "/").last.map(String.init) ?? path
        switch name {
        case "read_file": return file.isEmpty ? "Reading a file…" : "Reading \(file)…"
        case "list_dir": return path.isEmpty || path == "." ? "Looking around the library…" : "Looking into \(path)…"
        case "list_sources": return "Checking the sources…"
        case "rag_search", "search_documents": return "Searching the sources…"
        case "web_search", "web_fetch": return "Searching the web…"
        case "create_file": return file.isEmpty ? "Creating a file…" : "Creating \(file)…"
        case "append_file": return file.isEmpty ? "Writing…" : "Writing \(file)…"
        case "overwrite_file", "replace_in_file": return file.isEmpty ? "Editing…" : "Editing \(file)…"
        case "save_asset": return "Saving an image…"
        case "qa_deck": return "Checking the slides…"
        case "show_preview": return "Showing the preview…"
        case "todo_write", "todo_update": return "Planning…"
        case "load_skill": return "Loading guidance…"
        case "ask_user": return "Asking you…"
        default: return name.isEmpty ? "Working…" : "\(name.replacingOccurrences(of: "_", with: " ").capFirst)…"
        }
    }
}
