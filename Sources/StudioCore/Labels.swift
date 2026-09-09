import Foundation

/// Display names derived from folder names.
public enum Labels {
    static let codeRx = Rx("^([a-z]{2,4}\\d{3,4})(?:-(.+))?$", .caseInsensitive)

    public static func courseLabel(_ c: String, _ meta: LectureMeta? = nil) -> String {
        if c == "(root)" { return "Repository files" }
        if let t = meta?.title, !t.isEmpty { return (meta?.code).map { $0.isEmpty ? t : "\($0) \(t)" } ?? t }
        guard let m = codeRx.first(c) else { return c.split(separator: "-").map { String($0).capFirst }.joined(separator: " ") }
        let rest = (m[2] ?? "").split(separator: "-").map { String($0).capFirst }.joined(separator: " ")
        let code = (m[1] ?? "").uppercased()
        return rest.isEmpty ? code : "\(code) \(rest)"
    }

    /// "week3" -> "Week 3", "session-2" -> "Session 2", "calistay1" -> "Workshop 1", "" -> the course root.
    public static func unitLabel(_ u: String, talk: Bool = false) -> String {
        if u.isEmpty { return talk ? "Talk files" : "Course files" }
        if let c = Rx("^calistay-?(\\d+)$", .caseInsensitive).first(u) { return "Workshop \(c[1] ?? "")" }
        if let m = Rx("^([a-z]+?)-?(\\d+)$", .caseInsensitive).first(u) { return "\((m[1] ?? "").lowercased().capFirst) \(m[2] ?? "")" }
        return u.split(separator: "-").map { String($0).capFirst }.joined(separator: " ")
    }

    /// The word used for one unit of this lecture: "week", "session"...
    public static func unitWord(_ meta: LectureMeta?, units: [String] = []) -> String {
        if let p = meta?.unitPrefix, !p.isEmpty { return p }
        var counts: [String: Int] = [:]
        let rx = Rx("^([a-z]+?)-?\\d+$", .caseInsensitive)
        for u in units { if let m = rx.first(u) { counts[(m[1] ?? "").lowercased(), default: 0] += 1 } }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "week"
    }

    public static func sortUnits(_ a: String, _ b: String) -> Bool {
        if a == "" { return true }
        if b == "" { return false }
        return a.compare(b, options: [.numeric]) == .orderedAscending
    }

    public static func courseCode(_ c: String, _ meta: LectureMeta? = nil) -> String {
        if let code = meta?.code, !code.isEmpty { return code }
        return (Rx("^([a-z]{2,4}\\d{3,4})(?:-|$)", .caseInsensitive).first(c)?[1] ?? "").uppercased()
    }

    public static func courseTitle(_ c: String, _ meta: LectureMeta? = nil) -> String {
        if let t = meta?.title, !t.isEmpty { return t }
        return Rx("^[A-Z0-9]+ ").replace(courseLabel(c), with: "")
    }

    public static func isTalk(_ meta: LectureMeta?) -> Bool { meta?.kind == .talk }

    /// The plural shown on cards: "3 weeks", "2 workshops".
    public static func plural(_ word: String, _ n: Int) -> String {
        word == "calistay" ? "\(n) workshop\(n == 1 ? "" : "s")" : "\(n) \(word)\(n == 1 ? "" : "s")"
    }
}

/// Speaker notes and slide arithmetic on the deck source. `starts` comes from the preview's Marp parser.
public enum Slides {
    /// 0-based slide index that contains the 0-based line.
    public static func slideForLine(_ starts: [Int], _ line: Int) -> Int {
        var lo = 0
        var hi = starts.count - 1
        if hi < 0 { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if starts[mid] <= line { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    static let directive = Rx("^_?(marp|theme|style|headingDivider|lang|size|math|paginate|header|footer|class|backgroundColor|backgroundImage|backgroundPosition|backgroundRepeat|backgroundSize|background\\w*|color|title|description|author|keywords|url|image|transition)\\s*:", .caseInsensitive)
    static let comment = Rx("<!--([\\s\\S]*?)-->")

    /// Presenter notes of one slide: the HTML comments that are not Marp directives.
    public static func notes(_ markdown: String, starts: [Int], index: Int) -> [String] {
        let lines = markdown.jsLines
        let from = index < starts.count ? starts[index] : 0
        let to = index + 1 < starts.count ? starts[index + 1] : lines.count
        guard from < to, from < lines.count else { return [] }
        let text = lines[from..<min(to, lines.count)].joined(separator: "\n")
        var out: [String] = []
        for m in comment.all(text) {
            let body = (m[1] ?? "").trimmed
            if body.isEmpty || directive.test(body) { continue }
            out.append(body)
        }
        return out
    }
}

/// Folder of a repo path, "." for a file at the root.
public func deckDir(_ path: String) -> String {
    guard let i = path.lastIndex(of: "/") else { return "." }
    return String(path[..<i])
}
