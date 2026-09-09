import SwiftUI
import StudioCore

/// The three-panel workspace: chat, preview, editor.
struct WorkspaceView: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var visible: [PanelId] { store.panelOrder.filter { !store.hiddenPanels.contains($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SplitPanels(ids: visible, fractions: Binding(get: { store.panelFractions }, set: { store.panelFractions = $0 }), minWidth: 240, onCommit: { store.savePanelFractions() }) { p in
                panel(p)
            }
            if store.gitAvailable { GitBarView() }
        }
        .onAppear { store.editor.setDark(colorScheme == .dark) }
        .onChange(of: colorScheme) { _, c in store.editor.setDark(c == .dark) }
    }

    var header: some View {
        let unitItems = Array(Set(store.files.filter { $0.course == store.course }.map(\.unit))).sorted(by: Labels.sortUnits)
        let fileItems = store.unitFiles.map(\.path) + (!store.filePath.isEmpty && !store.unitFiles.contains { $0.path == store.filePath } ? [store.filePath] : [])
        return HStack(spacing: 8) {
            Button { store.backToUnits() } label: { Image(systemName: "arrow.left") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Back to the units")
            Button(Labels.courseLabel(store.course, store.meta)) { store.backToUnits() }.buttonStyle(.plain).font(.callout)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            Picker("", selection: Binding(get: { store.unit ?? "" }, set: { u in
                let list = store.files.filter { $0.course == store.course && $0.unit == u }
                let main = list.first { $0.kind == .deck } ?? list.first { $0.kind == .md } ?? list.first
                store.unit = u
                if let main { Task { await store.openFile(main.path, select: false) } }
            })) {
                ForEach(unitItems, id: \.self) { Text(Labels.unitLabel($0, talk: store.talk)).tag($0) }
            }.labelsHidden().fixedSize()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            Picker("", selection: Binding(get: { store.filePath }, set: { p in if !p.isEmpty { Task { await store.openFile(p, select: false) } } })) {
                if store.filePath.isEmpty { Text("Choose a file").tag("") }
                ForEach(fileItems, id: \.self) { p in Text(store.unitFiles.contains { $0.path == p } ? (p as NSString).lastPathComponent : p).tag(p) }
            }.labelsHidden().fixedSize().font(.system(.caption, design: .monospaced))
            Button { store.dialog = .file } label: { Image(systemName: "doc.badge.plus") }.buttonStyle(.plain).foregroundStyle(.secondary).help("New file in this \(store.word)")
            Button { store.dialog = .sources } label: {
                HStack(spacing: 4) { Image(systemName: "book"); Text("Sources"); if store.sourceCount > 0 { Chip(text: "\(store.sourceCount)", filled: true) } }
            }.controlSize(.small).help(store.talk ? "Source materials for this talk" : "Source materials for this course and \(store.word)")
            if store.dirty { Chip(text: "Unsaved") }
            if store.staleOnDisk { Button("Changed on disk, reload") { store.reloadFromDisk() }.controlSize(.small).help("This file changed on disk (the assistant, another app, a pull) while you had unsaved edits.") }
            Button { Task { await store.refreshLibrary() } } label: { Image(systemName: "arrow.clockwise") }.controlSize(.small).help("Read the library folder again (⌘R). Changes from other apps normally show up on their own.")
            Spacer()
            if store.isText {
                Button { Task { await store.save() } } label: { Label("Save ⌘S", systemImage: "square.and.arrow.down") }.controlSize(.small).disabled(!store.dirty).buttonStyle(store.dirty ? .prominent : .plainBordered)
            }
            Divider().frame(height: 16)
            ForEach(store.panelOrder) { p in
                Toggle(isOn: Binding(get: { !store.hiddenPanels.contains(p) }, set: { _ in store.togglePanel(p) })) { Image(systemName: icon(p)) }.toggleStyle(.button).controlSize(.small).help("\(store.hiddenPanels.contains(p) ? "Show" : "Hide") \(p.rawValue)")
            }
            Divider().frame(height: 16)
            if store.isDeck {
                Button { store.startPresentation() } label: { Label("Present", systemImage: "play.rectangle") }.controlSize(.small).help("Presenter mode: slides on the other screen, notes here (⌥⌘P)")
            }
            if store.isDeck {
                Toggle(isOn: Binding(get: { store.showNotes }, set: { _ in store.toggleNotes() })) { Image(systemName: "note.text") }.toggleStyle(.button).controlSize(.small).help(store.showNotes ? "Hide speaker notes" : "Show speaker notes under the preview")
            }

        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    func icon(_ p: PanelId) -> String { p == .chat ? "bubble.left" : p == .preview ? "play.rectangle" : "pencil.line" }

    @ViewBuilder
    func panel(_ p: PanelId) -> some View {
        VStack(spacing: 0) {
            PanelHeader(icon: icon(p), title: p.rawValue) {
                let i = store.panelOrder.firstIndex(of: p) ?? 0
                HStack(spacing: 2) {
                    Button { store.movePanel(p, by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(i == 0).help("Move left")
                    Button { store.movePanel(p, by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(i == store.panelOrder.count - 1).help("Move right")
                    Button { store.togglePanel(p) } label: { Image(systemName: "eye.slash") }.buttonStyle(.plain).help("Hide this panel")
                }
            }
            switch p {
            case .chat:
                ChatView(scopes: store.weekScope.map { [$0, store.lectureScope] } ?? [store.lectureScope], defaultKey: store.weekScope?.key ?? store.lectureScope.key)
            case .preview:
                PreviewPanel()
            case .editor:
                if store.isText {
                    VStack(spacing: 0) {
                        if store.isDeck { MarpToolbar(editor: store.editor); Divider() }
                        WebViewHost(webView: store.editor.webView)
                    }
                }
                else if store.filePath.isEmpty { EmptyBlock(icon: "doc.text.magnifyingglass", title: "Choose a file", description: "Pick a file from the breadcrumb above, or create one with the + button.") }
                else { EmptyBlock(icon: "doc.text.magnifyingglass", title: "No text editor for this file", description: "Use the preview, or open it in its own app from there.") }
            }
        }
    }
}

struct PreviewPanel: View {
    @Environment(StudioStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if store.filePath.isEmpty {
                    EmptyBlock(icon: "doc.text.magnifyingglass", title: "Choose a file", description: "Pick a file from the breadcrumb above, or create one with the + button.")
                } else if store.isDeck {
                    qaBar
                    Divider()
                    WebViewHost(webView: store.preview.webView)
                    if store.showNotes { notesStrip }
                } else {
                    DocPreviewView(path: store.filePath, kind: store.kind)
                }
            }
            if store.isDeck {
                Divider()
                SlideRail(count: store.slideCount, current: store.current, overflow: Set(store.qa?.overflowPages ?? []), missing: Set(store.qa?.missingImagePages ?? [])) { store.goToSlide($0, from: "rail") }
            }
        }
    }

    var qaBar: some View {
        HStack(spacing: 8) {
            Text("\(store.slideCount) slides").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button { Task { await store.runQa() } } label: { BusyLabel(busy: store.qaBusy, idle: "Check slides", working: "Checking…") }.controlSize(.small).disabled(store.qaBusy)
            if let qa = store.qa {
                if qa.overflowPages.isEmpty && qa.missingImagePages.isEmpty {
                    Chip(text: "No overflow, no missing images", icon: "checkmark.circle", tint: .green, filled: true)
                } else {
                    FlowRow(spacing: 3) {
                        ForEach(qa.overflowPages, id: \.self) { p in
                            Button { store.goToSlide(p - 1, from: "rail") } label: { Chip(text: "\(p)", tint: .red, filled: true) }.buttonStyle(.plain).help("Slide \(p): overflow")
                        }
                        ForEach(qa.missingImagePages, id: \.self) { p in
                            Button { store.goToSlide(p - 1, from: "rail") } label: { Chip(text: "\(p)", icon: "exclamationmark.triangle", tint: .orange) }.buttonStyle(.plain).help("Slide \(p): missing image")
                        }
                    }
                }
            }
            if let e = store.previewError { Text(e).font(.caption).foregroundStyle(.red).lineLimit(1) }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    var notesStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Speaker notes, slide \(store.current + 1)", systemImage: "note.text").font(.caption2.weight(.medium)).textCase(.uppercase).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if store.notes.isEmpty {
                        Text("No notes on this slide. Add an HTML comment to the slide, or ask the chat for speaker notes.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.notes.enumerated()), id: \.offset) { _, n in Text(n).textSelection(.enabled) }
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxHeight: 160)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        .overlay(alignment: .top) { Divider() }
    }
}

/// One tick per slide; the current slide is the wide tick. Red = overflow, amber = missing image.
struct SlideRail: View {
    var count: Int
    var current: Int
    var overflow: Set<Int>
    var missing: Set<Int>
    var onSelect: (Int) -> Void
    @State private var hover: Int?

    var body: some View {
        GeometryReader { geo in
            let h = count > 0 ? max(3, min(12, (geo.size.height - 16) / CGFloat(count) - 1)) : 0
            VStack(spacing: 1) {
                ForEach(0..<count, id: \.self) { i in
                    let page = i + 1
                    let color: Color = overflow.contains(page) ? .red : missing.contains(page) ? .orange : (i == current ? .primary : .secondary.opacity(0.4))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: i == current || hover == i ? 12 : 6, height: h)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hover = $0 ? i : nil }
                        .onTapGesture { onSelect(i) }
                        .help("Slide \(page)\(overflow.contains(page) ? ", overflow" : missing.contains(page) ? ", missing image" : "")")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 20)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
    }
}


/// Marp building blocks, inserted at the cursor of the editor. Mirrors what a deck author reaches for
/// most: a new slide, a lead slide, two columns, an image, a speaker note, a directive.
struct MarpToolbar: View {
    @Environment(StudioStore.self) private var store
    let editor: EditorController

    struct Block: Identifiable { var id: String { label }; var label: String; var icon: String; var snippet: String; var help: String }

    static let blocks: [Block] = [
        Block(label: "Slide", icon: "rectangle.badge.plus", snippet: "\n---\n\n# {cursor}\n\n", help: "New slide with a title"),
        Block(label: "Lead", icon: "text.alignleft", snippet: "\n---\n\n<!-- _class: lead -->\n\n# {cursor}\n\n", help: "New title slide (lead class)"),
        Block(label: "Columns", icon: "rectangle.split.2x1", snippet: "<div class=\"two-columns\">\n<div class=\"column\">\n\n### {cursor}\n\n- \n\n</div>\n<div class=\"column\">\n\n### \n\n- \n\n</div>\n</div>\n", help: "Two-column block"),
        Block(label: "Image", icon: "photo", snippet: "![bg right contain](./assets/{cursor}.png)\n", help: "Background image on the right (assets/ folder)"),
        Block(label: "Note", icon: "note.text", snippet: "<!-- {cursor} -->\n", help: "Speaker note (HTML comment; shown under the preview and in presenter mode)"),
        Block(label: "Code", icon: "chevron.left.forwardslash.chevron.right", snippet: "```{cursor}\n\n```\n", help: "Fenced code block; type the language after the backticks"),
        Block(label: "Table", icon: "tablecells", snippet: "| {cursor} | | |\n|---|---|---|\n| | | |\n", help: "Table"),
        Block(label: "Quote", icon: "text.quote", snippet: "> {cursor}\n", help: "Quote"),
    ]

    static let directives: [(String, String)] = [
        ("Lead slide (_class: lead)", "<!-- _class: lead -->\n"),
        ("No page number (_paginate: false)", "<!-- _paginate: false -->\n"),
        ("No header on this slide", "<!-- _header: \"\" -->\n"),
        ("No footer on this slide", "<!-- _footer: \"\" -->\n"),
        ("Background colour", "<!-- _backgroundColor: #{cursor}f5f5f5 -->\n"),
        ("Invert colours", "<!-- _class: invert -->\n"),
    ]

    var body: some View {
        // Labels when there is room, icons only when the editor is narrow; nothing wraps.
        ViewThatFits(in: .horizontal) {
            row(titled: true)
            row(titled: false)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder
    func row(titled: Bool) -> some View {
        HStack(spacing: titled ? 6 : 4) {
            ForEach(Self.blocks) { b in
                Button { editor.insertBlock(b.snippet) } label: {
                    if titled { Label(b.label, systemImage: b.icon).labelStyle(.titleAndIcon).fixedSize() } else { Image(systemName: b.icon) }
                }.help(b.help)
            }
            Menu {
                ForEach(Self.directives, id: \.0) { d in Button(d.0) { editor.insertBlock(d.1) } }
            } label: {
                if titled { Label("Directive", systemImage: "chevron.left.slash.chevron.right").labelStyle(.titleAndIcon).fixedSize() } else { Image(systemName: "chevron.left.slash.chevron.right") }
            }
            .menuStyle(.borderlessButton).fixedSize().help("Per-slide Marp directive")
            Spacer(minLength: 4)
            Button { store.dialog = .marpHelp } label: { Image(systemName: "questionmark.circle") }.help("How decks work: Marp Markdown, slides, directives, images, notes")
        }
        .lineLimit(1)
    }
}


/// Side-by-side panels with draggable dividers. Widths are shares keyed by panel id, so hiding,
/// showing or reordering a panel never resets the others.
struct SplitPanels<Content: View>: View {
    let ids: [PanelId]
    @Binding var fractions: [PanelId: CGFloat]
    var minWidth: CGFloat = 240
    var onCommit: () -> Void = {}
    @ViewBuilder let content: (PanelId) -> Content
    @State private var dragStart: [PanelId: CGFloat]? = nil

    func widths(total: CGFloat) -> [PanelId: CGFloat] {
        let dividers = CGFloat(max(0, ids.count - 1)) * 1
        let avail = max(0, total - dividers)
        let sum = ids.reduce(0) { $0 + (fractions[$1] ?? 0.33) }
        var out: [PanelId: CGFloat] = [:]
        for id in ids { out[id] = avail * (fractions[id] ?? 0.33) / max(sum, 0.0001) }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let w = widths(total: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    content(id).frame(width: w[id] ?? 0)
                    if i < ids.count - 1 {
                        divider(left: id, right: ids[i + 1], total: geo.size.width)
                    }
                }
            }
        }
    }

    func divider(left: PanelId, right: PanelId, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(Rectangle().fill(Color.clear).frame(width: 9).contentShape(Rectangle()))
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if dragStart == nil { dragStart = fractions }
                        guard let start = dragStart else { return }
                        let sum = ids.reduce(0) { $0 + (start[$1] ?? 0.33) }
                        let avail = max(1, total - CGFloat(ids.count - 1))
                        let delta = g.translation.width / avail * sum
                        let l0 = start[left] ?? 0.33, r0 = start[right] ?? 0.33
                        let minF = minWidth / avail * sum
                        var l = l0 + delta, r = r0 - delta
                        if l < minF { r -= (minF - l); l = minF }
                        if r < minF { l -= (minF - r); r = minF }
                        var f = fractions
                        f[left] = l
                        f[right] = r
                        fractions = f
                    }
                    .onEnded { _ in dragStart = nil; onCommit() }
            )
    }
}
