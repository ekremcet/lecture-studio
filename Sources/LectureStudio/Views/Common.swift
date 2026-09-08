import SwiftUI
import AppKit
import WebKit

/// Hosts a WKWebView that a controller owns, so the view can unmount without losing the page.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// A small uppercase label, the panel headers of the web app.
struct PanelHeader<Trailing: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(title.uppercased()).font(.caption2.weight(.medium)).tracking(0.6)
            Spacer()
            trailing
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The shadcn `Empty` block: an icon, a title, a line of help, optional actions.
struct EmptyBlock<Content: View>: View {
    var icon: String
    var title: String
    var description: String?
    @ViewBuilder var content: Content

    init(icon: String, title: String, description: String? = nil, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.icon = icon; self.title = title; self.description = description; self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
                .frame(width: 40, height: 40).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.headline)
            if let d = description { Text(d).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Chip: View {
    var text: String
    var icon: String? = nil
    var tint: Color = .secondary
    var filled = false
    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9)) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(filled ? tint.opacity(0.15) : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(filled ? Color.clear : Color.secondary.opacity(0.3)))
        .foregroundStyle(tint)
    }
}

extension View {
    /// A sheet form with the dialog chrome the web app uses: title, description, fields, footer.
    func dialogFrame(width: CGFloat = 520) -> some View { self.padding(20).frame(width: width) }
}

struct DialogHeader: View {
    var title: String
    var icon: String? = nil
    var description: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.title3.weight(.semibold))
            }
            Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LabeledField<Content: View>: View {
    var label: String
    var hint: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            content
            if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

let UNIT_WORDS = ["week", "session", "module", "lecture", "day", "part"]

struct UnitPicker: View {
    @Binding var value: String
    var body: some View {
        Picker("", selection: $value) {
            ForEach(UNIT_WORDS, id: \.self) { Text("\($0)s").tag($0) }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if !UNIT_WORDS.contains(value) { value = "week" } }
    }
}

struct BusyLabel: View {
    var busy: Bool
    var idle: String
    var working: String
    var body: some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.small) }
            Text(busy ? working : idle)
        }
    }
}

extension FileKind {
    var symbol: String {
        switch self {
        case .deck, .pptx: return "rectangle.on.rectangle"
        case .md, .docx: return "doc.text"
        case .pdf: return "doc.richtext"
        case .xlsx: return "tablecells"
        case .image: return "photo"
        case .text: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }
}
import StudioCore


/// Season + year instead of free text, so terms sort, compare and archive without ambiguity.
/// Binds to the stored string ("Fall 2026"); an unparseable existing value is shown as custom text.
struct TermPicker: View {
    @Binding var text: String
    @State private var season = "Fall"
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var custom = false

    var body: some View {
        HStack(spacing: 6) {
            if custom {
                TextField("Term", text: $text)
                Button { custom = false; push() } label: { Image(systemName: "calendar") }.buttonStyle(.plain).help("Pick season and year instead")
            } else {
                Picker("", selection: $season) { ForEach(TermValue.seasons, id: \.self) { Text($0).tag($0) } }.labelsHidden().fixedSize().onChange(of: season) { _, _ in push() }
                Stepper(value: $year, in: 2000...2100) { Text(String(year)).monospacedDigit().frame(width: 40) }.onChange(of: year) { _, _ in push() }
            }
        }
        .onAppear {
            if let t = TermValue.parse(text) { season = t.season; year = t.year }
            else if !text.trimmed.isEmpty { custom = true }
            else { push() }
        }
    }

    func push() { text = TermValue(season: season, year: year).text }
}


/// Open the Settings window (the Agent tab holds the Oberik connection).
@MainActor
func openSettingsWindow() {
    if #available(macOS 14, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    else { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }
}

let oberikURL = URL(string: "https://oberik.com/")!
/// The step-by-step guide with screenshots on the app's site.
let oberikGuideURL = URL(string: "https://lecture.studio/setup/oberik/")!
