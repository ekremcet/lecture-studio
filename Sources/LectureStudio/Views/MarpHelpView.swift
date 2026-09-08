import SwiftUI
import AppKit

/// What a deck is and what renders: Marp Markdown in one page, with links to the full documentation.
struct MarpHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable { let id = UUID(); var what: String; var how: String }

    let basics: [Row] = [
        Row(what: "A deck is a Markdown file", how: "Plain text you can read, diff and version. The preview renders it with Marp; nothing is stored in a proprietary format."),
        Row(what: "Slides", how: "A line with only --- starts a new slide. Everything between two separators is one slide, 16:9 at 1280×720."),
        Row(what: "Front matter", how: "The block between the first two --- lines: marp: true, paginate, header, footer, size, theme, math, and a style block for the whole deck."),
        Row(what: "Per-slide directives", how: "HTML comments such as <!-- _class: lead --> or <!-- _paginate: false --> apply to that slide only (the underscore means \"this slide\")."),
        Row(what: "Speaker notes", how: "Any other HTML comment on a slide is a note: shown under the preview and in presenter mode, never on the slide."),
    ]
    let content: [Row] = [
        Row(what: "Text", how: "Headings, bold, italic, lists, quotes, links, tables (GitHub flavour) and fenced code with syntax highlighting."),
        Row(what: "Images", how: "![alt](./assets/file.png) from the unit's assets folder. Marp extras: ![bg](…) for a background, ![bg right](…) or ![bg left:40%](…) for a split, ![w:400](…) to size."),
        Row(what: "Columns and HTML", how: "HTML is enabled: <div class=\"two-columns\"><div class=\"column\">…</div></div> gives two columns with the house style; small inline styles work too."),
        Row(what: "Math", how: "$…$ and $$…$$ when the front matter has math: mathjax."),
        Row(what: "Themes", how: "The app ships the ytu-lecture and ytu-talk themes (a lecture and a talk style); the default Marp theme is used when a deck names none. A style: | block in the front matter overrides sizes, colours and spacing."),
        Row(what: "Checks", how: "\"Check slides\" renders every slide and flags text that runs past the slide edge or images that fail to load; the same check is available to the assistant as qa_deck."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "How decks work", icon: "rectangle.on.rectangle", description: "Lecture Studio decks are Marp Markdown. The editor is a text editor with helpers; the preview is what Marp renders; export to PDF or PowerPoint uses the Marp toolchain.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("The file", basics)
                    section("What renders", content)
                }
            }
            .frame(maxHeight: 460)
            HStack {
                Button { NSWorkspace.shared.open(URL(string: "https://marpit.marp.app/markdown")!) } label: { Label("Marp Markdown reference", systemImage: "book") }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .dialogFrame(width: 720)
    }

    func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.medium)).tracking(0.6).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider() }
                    HStack(alignment: .top, spacing: 12) {
                        Text(r.what).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
                        Text(r.how).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
