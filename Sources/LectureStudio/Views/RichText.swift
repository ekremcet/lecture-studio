import SwiftUI
import AppKit
import StudioCore

/// A finished assistant reply: the parsed markdown as one native text view. One view per message keeps
/// the transcript cheap whatever the length of a reply (a SwiftUI tree of stacks and texts is hundreds
/// of items per reply and every tick of the stream walks them all), gives an exact height (a lazy stack
/// estimated tall rows and cut their ends off), and brings native selection and link clicks.
struct RichText: NSViewRepresentable {
    let text: String
    static let maxWidth: CGFloat = 520

    final class TextView: NSTextView {
        var storageText = ""
    }

    func makeNSView(context: Context) -> TextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: Self.maxWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let tv = TextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateNSView(_ tv: TextView, context: Context) {
        guard tv.storageText != text else { return }
        tv.storageText = text
        tv.textStorage?.setAttributedString(RichTextCache.shared.attributed(text))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: TextView, context: Context) -> CGSize? {
        guard let container = tv.textContainer, let layout = tv.layoutManager else { return nil }
        let proposed = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Self.maxWidth
        container.containerSize = CGSize(width: proposed, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        var used = layout.usedRect(for: container)
        // A short reply keeps a narrow bubble: the width is what the lines use, up to the proposal. The
        // height is measured again at that width, the one the view is placed at: measured at the wider
        // proposal, a long reply wrapped taller than reported and its end ran past the transcript.
        let width = min(proposed, ceil(used.width) + 1)
        if width < proposed {
            container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            used = layout.usedRect(for: container)
        }
        return CGSize(width: width, height: ceil(used.height))
    }
}

/// Markdown blocks to one attributed string, built once per text. Fonts follow the SwiftUI text styles
/// the transcript used before (body, headline, subheadline, caption for code), colors are dynamic.
final class RichTextCache {
    static let shared = RichTextCache()
    private let cache: NSCache<NSString, NSAttributedString> = { let c = NSCache<NSString, NSAttributedString>(); c.countLimit = 400; return c }()

    func attributed(_ text: String) -> NSAttributedString {
        if let hit = cache.object(forKey: text as NSString) { return hit }
        let a = Self.render(ChatMarkdown.cached(text))
        cache.setObject(a, forKey: text as NSString)
        return a
    }

    static let body = NSFont.preferredFont(forTextStyle: .body)
    static let headline = NSFont.preferredFont(forTextStyle: .headline)
    static let subheadline: NSFont = {
        let f = NSFont.preferredFont(forTextStyle: .subheadline)
        return NSFont.systemFont(ofSize: f.pointSize, weight: .semibold)
    }()
    static let code = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)

    static func render(_ blocks: [ChatBlock]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func paragraph(spacing: CGFloat, indent: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = spacing
            p.lineBreakMode = .byWordWrapping
            if indent > 0 {
                p.headIndent = indent
                p.firstLineHeadIndent = 0
                p.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                p.defaultTabInterval = indent
            }
            return p
        }
        func append(_ s: NSAttributedString, style: NSParagraphStyle, last: Bool) {
            let m = NSMutableAttributedString(attributedString: s)
            m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
            out.append(m)
            if !last { out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: body])) }
        }
        for (bi, b) in blocks.enumerated() {
            let last = bi == blocks.count - 1
            switch b {
            case .paragraph(let p):
                append(inline(p, base: body), style: paragraph(spacing: 6), last: last)
            case .heading(let level, let h):
                append(inline(h, base: level <= 2 ? headline : subheadline), style: paragraph(spacing: 6), last: last)
            case .bullet(let items):
                for (i, it) in items.enumerated() {
                    let line = NSMutableAttributedString(string: "•\t", attributes: [.font: body, .foregroundColor: NSColor.labelColor])
                    line.append(inline(it, base: body))
                    let lastItem = i == items.count - 1
                    append(line, style: paragraph(spacing: lastItem ? 6 : 2, indent: 14), last: last && lastItem)
                }
            case .numbered(let items):
                for (i, it) in items.enumerated() {
                    let line = NSMutableAttributedString(string: "\(i + 1).\t", attributes: [.font: body, .foregroundColor: NSColor.labelColor])
                    line.append(inline(it, base: body))
                    let lastItem = i == items.count - 1
                    append(line, style: paragraph(spacing: lastItem ? 6 : 2, indent: 20), last: last && lastItem)
                }
            case .code(let c):
                let s = NSAttributedString(string: c, attributes: [.font: code, .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)])
                append(s, style: paragraph(spacing: 6), last: last)
            }
        }
        return out
    }

    /// Inline markdown (bold, italic, code, links) as font traits and link attributes.
    static func inline(_ a: AttributedString, base: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in a.runs {
            let piece = String(a[run.range].characters)
            var font = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular) }
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            if intent.contains(.code) { attrs[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.08) }
            if let link = run.link { attrs[.link] = link }
            out.append(NSAttributedString(string: piece, attributes: attrs))
        }
        return out
    }
}
