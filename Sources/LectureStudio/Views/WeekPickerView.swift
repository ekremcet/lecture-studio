import SwiftUI
import AppKit
import StudioCore

/// Second screen: the units of one course with their files, and the course chat on the right.
struct WeekPickerView: View {
    @Environment(StudioStore.self) private var store

    var units: [(unit: String, files: [FileInfo])] {
        var map: [String: [FileInfo]] = [:]
        for f in store.files where f.course == store.course { map[f.unit, default: []].append(f) }
        return map.keys.sorted(by: Labels.sortUnits).map { ($0, map[$0]!) }
    }

    func primary(_ list: [FileInfo]) -> FileInfo { list.first { $0.kind == .deck } ?? list.first { $0.kind == .md } ?? list[0] }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView { content.padding(.horizontal, 32).padding(.vertical, 28).frame(maxWidth: 1100).frame(maxWidth: .infinity) }
            Divider()
            VStack(spacing: 0) {
                PanelHeader(icon: "bubble.left", title: store.talk ? "Talk chat" : "Course chat") {
                    Button { store.dialog = .sources } label: {
                        HStack(spacing: 4) { Image(systemName: "book"); Text("Sources"); if store.sourceCount > 0 { Chip(text: "\(store.sourceCount)", filled: true) } }
                    }.controlSize(.small)
                }
                ChatView(scopes: [store.lectureScope], defaultKey: store.lectureScope.key)
            }
            .frame(width: 420)
        }
    }

    var content: some View {
        let talk = store.talk
        let word = store.word
        let list = units
        let noUnits = !talk && !list.contains { !$0.unit.isEmpty }
        return VStack(alignment: .leading, spacing: 12) {
            Button { store.backToLectures() } label: { Label("All lectures", systemImage: "arrow.left") }.buttonStyle(.plain).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(Labels.courseLabel(store.course, store.meta)).font(.title.weight(.semibold))
                        Button { store.dialog = .editLecture } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(.secondary).help(talk ? "Edit talk" : "Edit course")
                    }
                    termsRow
                }
                Spacer()
                if !talk { Button { store.dialog = .week } label: { Label("New \(word)", systemImage: "plus") } }
                Menu {
                    Button { store.dialog = .newTerm } label: { Label("New term from this course…", systemImage: "calendar.badge.plus") }
                    Button { store.dialog = .compare } label: { Label("Compare with another term…", systemImage: "arrow.left.arrow.right") }.disabled(store.terms(of: store.course).count < 2)
                    Divider()
                    Button(talk ? "Make this a course (numbered \(word)s)" : "Make this a talk (one deck)") { store.setKind(store.course, talk ? .course : .talk) }
                    Button(store.meta?.archived == true ? "Unarchive" : "Archive") { store.setArchived(store.course, store.meta?.archived != true) }
                    Divider()
                    Button { store.setExcluded(store.course, true) } label: { Label("Hide from the studio (not a course or a talk)", systemImage: "eye.slash") }
                    Button(role: .destructive) { store.dialog = .remove } label: { Label("Remove…", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.button).menuIndicator(.hidden).fixedSize().help("Terms, comparison, archive")
            }
            VStack(spacing: 0) {
                if list.isEmpty || noUnits {
                    EmptyBlock(icon: "calendar", title: "No \(word)s yet", description: store.sourceCount > 0
                        ? "The course has \(store.sourceCount) source file\(store.sourceCount == 1 ? "" : "s"). Create the first \(word); its deck opens with a title slide, and the chat can outline it from the sources."
                        : "Create the first \(word) to start writing its deck. Adding the readings first lets the assistant draft from them and cite them, but either order works.") {
                        VStack(spacing: 10) {
                            HStack {
                                Button { store.dialog = .week } label: { Label("New \(word)", systemImage: "plus") }.buttonStyle(.borderedProminent)
                                Button { store.dialog = .sources } label: { Label(store.sourceCount > 0 ? "Sources" : "Add course sources", systemImage: "book") }
                            }
                            if list.contains(where: { $0.unit.isEmpty && $0.files.contains { $0.kind == .deck } }) {
                                Button { store.setKind(store.course, .talk) } label: { Label("This is a talk, not a course", systemImage: "mic") }.buttonStyle(.link).controlSize(.small)
                            }
                        }
                    }
                }
                // Numbered units only; everything else (course root files, research, scripts) folds below.
                let numbered = talk ? list.filter { $0.unit.isEmpty } : list.filter { parseUnit($0.unit) != nil }
                let other = list.filter { u in !numbered.contains { $0.unit == u.unit } }
                ForEach(Array(numbered.enumerated()), id: \.element.unit) { idx, entry in
                    if idx > 0 { Divider() }
                    unitRow(entry.unit, entry.files, compact: !talk)
                }
                if !other.isEmpty {
                    Divider()
                    // The whole bar toggles, not only the chevron.
                    Button { withAnimation(.easeOut(duration: 0.15)) { showOther.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(showOther ? 90 : 0))
                            Text("Other files (\(other.reduce(0) { $0 + $1.files.count }))").font(.callout)
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showOther {
                        Divider()
                        ForEach(Array(other.enumerated()), id: \.element.unit) { idx, entry in
                            if idx > 0 { Divider() }
                            unitRow(entry.unit, entry.files, compact: false)
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
    }

    /// The term line: the folder and the archive state; below it, when the course has several terms,
    /// a row of term tabs with the open one selected.
    var termsRow: some View {
        let all = store.terms(of: store.course)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let term = store.meta?.term, !term.isEmpty { Text(term) }
                Button { if let u = try? store.repo?.resolve(store.course) { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: { Chip(text: store.course, icon: "folder") }
                    .buttonStyle(.plain).help("Show the folder in Finder")
                    .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                if let web = store.webURL(forCourse: store.course) {
                    Button { NSWorkspace.shared.open(web) } label: { Chip(text: web.host?.contains("github") == true ? "GitHub" : "Repository", icon: "arrow.up.right.square") }
                        .buttonStyle(.plain).help(web.absoluteString)
                        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                if store.meta?.archived == true { Chip(text: "Archived", tint: .orange, filled: true) }
            }.font(.callout).foregroundStyle(.secondary)
            if all.count > 1 {
                HStack(spacing: 6) {
                    ForEach(all, id: \.self) { c in
                        let current = c == store.course
                        Button { if !current { store.selectCourse(c) } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: store.lectures[c]?.archived == true ? "archivebox" : "calendar").font(.caption)
                                Text(store.lectures[c]?.term ?? c).font(.callout.weight(current ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(current ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: Capsule())
                            .overlay(Capsule().strokeBorder(current ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.35)))
                            .foregroundStyle(current ? Color.accentColor : Color.primary)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(current ? "This term" : "Open \(store.lectures[c]?.term ?? c) (\(c))")
                        .onHover { inside in if inside && !current { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }
                }
            }
        }
    }

    @State private var showOther = false

    func unitRow(_ unit: String, _ list: [FileInfo], compact: Bool) -> some View {
        let main = primary(list)
        let deck = list.first { $0.kind == .deck }
        return HStack(alignment: .top, spacing: 12) {
            Button { store.openUnit(unit, path: main.path) } label: {
                HStack(spacing: 10) {
                    Text(Labels.unitLabel(unit, talk: store.talk)).font(.callout.weight(.medium)).frame(width: 96, alignment: .leading)
                    Text(deck?.title.isEmpty == false ? deck!.title : (main.title.isEmpty ? "\(list.count) files" : main.title)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            if compact {
                Text("\(list.count) file\(list.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.tertiary)
            } else {
            FlowRow(spacing: 4) {
                ForEach(list.prefix(6)) { f in
                    Button { store.openUnit(unit, path: f.path) } label: {
                        Chip(text: f.name.count > 22 ? String(f.name.prefix(20)) + "…" : f.name, icon: f.kind.symbol)
                    }.buttonStyle(.plain).help(f.path)
                }
                if list.count > 6 { Text("+\(list.count - 6)").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// A wrapping horizontal stack, for chips and starter buttons.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.width && x > 0 { rows.append([]); x = 0 }
            rows[rows.count - 1].append((s, sz))
            x += sz.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowW = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            let rowH = row.map(\.1.height).max() ?? 0
            var px = alignment == .trailing ? bounds.maxX - rowW : alignment == .center ? bounds.midX - rowW / 2 : bounds.minX
            for (s, sz) in row {
                s.place(at: CGPoint(x: px, y: y + (rowH - sz.height) / 2), proposal: ProposedViewSize(sz))
                px += sz.width + spacing
            }
            y += rowH + spacing
        }
    }
}
