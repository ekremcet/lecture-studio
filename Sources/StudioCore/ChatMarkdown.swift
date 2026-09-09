import Foundation

/// One block of a chat reply, with the inline markdown (bold, italic, code, links) already resolved.
public enum ChatBlock: Equatable {
    case paragraph(AttributedString)
    case heading(Int, AttributedString)
    case bullet([AttributedString])
    case numbered([AttributedString])
    case code(String)
}

/// The markdown the chat renders: paragraphs, bullet and numbered lists, headings, fenced code. The
/// parse is a pure function of the text, so `cached` memoises it: a transcript re-renders many times
/// while a reply streams, and parsing every visible message on each pass is what froze the app on
/// 2026-09-09 (a per-token re-parse and re-layout of a very long transcript).
public enum ChatMarkdown {
    public static func blocks(_ text: String) -> [ChatBlock] {
        var out: [ChatBlock] = []
        var para: [String] = []
        var list: [String] = []
        var numbered = false
        var code: [String]? = nil
        func flushPara() { if !para.isEmpty { out.append(.paragraph(inline(para.joined(separator: " ")))); para = [] } }
        func flushList() {
            if !list.isEmpty { out.append(numbered ? .numbered(list.map(inline)) : .bullet(list.map(inline))); list = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var c = code {
                if line.hasPrefix("```") { out.append(.code(c.joined(separator: "\n"))); code = nil } else { c.append(raw); code = c }
                continue
            }
            if line.hasPrefix("```") { flushPara(); flushList(); code = []; continue }
            if line.isEmpty { flushPara(); flushList(); continue }
            if let m = line.range(of: "^#{1,6} ", options: .regularExpression) {
                flushPara(); flushList()
                out.append(.heading(line.distance(from: line.startIndex, to: m.upperBound) - 1, inline(String(line[m.upperBound...]))))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushPara()
                if numbered { flushList() }
                numbered = false
                list.append(String(line.dropFirst(2)))
                continue
            }
            if let m = line.range(of: "^\\d+[.)] ", options: .regularExpression) {
                flushPara()
                if !numbered { flushList() }
                numbered = true
                list.append(String(line[m.upperBound...]))
                continue
            }
            if !list.isEmpty { list[list.count - 1] += " " + line; continue }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flushPara(); flushList()
        return out
    }

    /// Inline markdown to an attributed string; text that is not valid markdown stays as it is.
    public static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    /// The blocks of `text`, parsed once. Keyed by the whole text, so a message that is still
    /// streaming misses until it settles and finished messages hit for as long as they stay around.
    public static func cached(_ text: String) -> [ChatBlock] {
        let key = text as NSString
        if let hit = cache.object(forKey: key) { return hit.blocks }
        let b = Box(blocks(text))
        cache.setObject(b, forKey: key, cost: text.utf8.count)
        return b.blocks
    }

    private final class Box {
        let blocks: [ChatBlock]
        init(_ b: [ChatBlock]) { blocks = b }
    }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 400
        c.totalCostLimit = 8 << 20
        return c
    }()
}

/// Changes that wait to land together. The chat stream reports every token and every command-output
/// chunk as its own event; applying each one to the observed model re-renders the transcript per
/// event. Queue them here and drain once per tick, so the model changes at most a few times a second.
public struct PendingPatches<Value> {
    public typealias Patch = (inout Value) -> Void
    private var patches: [Patch] = []

    public init() {}
    public var isEmpty: Bool { patches.isEmpty }
    public var count: Int { patches.count }

    public mutating func add(_ p: @escaping Patch) { patches.append(p) }
    public mutating func clear() { patches.removeAll() }

    /// Applies every queued patch to `value`, in order, and empties the queue. False when nothing was queued.
    @discardableResult
    public mutating func drain(into value: inout Value) -> Bool {
        guard !patches.isEmpty else { return false }
        let ps = patches
        patches = []
        for p in ps { p(&value) }
        return true
    }
}
