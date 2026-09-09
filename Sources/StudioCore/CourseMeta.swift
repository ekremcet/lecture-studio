import Foundation

public struct ParsedUnit: Equatable, Sendable {
    public var prefix: String
    public var n: Int
    public var sep: String
}

/// `week3` -> (week, 3, ""); `calistay-3` -> (calistay, 3, "-"); anything else -> nil.
public func parseUnit(_ name: String) -> ParsedUnit? {
    guard let m = Rx("^([a-z]+?)(-?)(\\d+)$", .caseInsensitive).first(name), let n = Int(m[3] ?? "") else { return nil }
    return ParsedUnit(prefix: (m[1] ?? "").lowercased(), n: n, sep: m[2] ?? "")
}

/// Derive header conventions and existing units from the decks of a course folder.
public func courseMeta(fs: RepoFS, course: String) -> CourseMeta {
    let lecture = LectureMetaStore(fs: fs).read(course)
    let profile = ProfileStore(fs: fs).read()
    let codeFromFolder = (Rx("^([a-z]{2,4}\\d{3,4})(?:-|$)", .caseInsensitive).first(course)?[1] ?? "").uppercased()
    var meta = CourseMeta(
        code: lecture.code ?? codeFromFolder,
        courseName: lecture.title ?? "",
        math: false,
        boldWeekFooter: false,
        unitPrefix: lecture.unitPrefix ?? profile.unitLabel ?? "week",
        unitSep: "",
        kind: lecture.kind ?? .course,
        weeks: [],
        topics: [:]
    )
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: fs.root.appendingPathComponent(course).path) else { return meta }
    var prefixes: [String: Int] = [:]
    var units: [ParsedUnit] = []
    var headerName = ""
    let headerRx = Rx("^header:\\s*\"([^\"]*)\"", .anchorsMatchLines)
    let footerRx = Rx("^footer:\\s*\"([^\"]*)\"", .anchorsMatchLines)
    let boldRx = Rx("^\\*\\*\\w+\\s*\\d+\\*\\*")
    let topicRx = Rx("^\\w+\\s*\\d+\\s*:\\s*(.+)$")
    let mathRx = Rx("^math:\\s*mathjax", .anchorsMatchLines)
    let hmRx = Rx("^([A-Z0-9]+)\\s*-\\s*(.+)$")
    for e in entries {
        guard let u = parseUnit(e) else { continue }
        prefixes[u.prefix, default: 0] += 1
        units.append(u)
        guard let text = try? fs.readString("\(course)/\(e)/\(e)-slides.md") else { continue }
        let head = String(text.prefix(3000))
        if let header = headerRx.first(head)?[1], !header.isEmpty, headerName.isEmpty {
            if let hm = hmRx.first(header) {
                if lecture.code == nil { meta.code = hm[1] ?? "" }
                headerName = (hm[2] ?? "").trimmed
            } else {
                headerName = header
            }
        }
        let footer = footerRx.first(head)?[1] ?? ""
        if boldRx.test(footer) { meta.boldWeekFooter = true }
        if let topic = topicRx.first(footer.replacingOccurrences(of: "**", with: ""))?[1] { meta.topics[u.n] = topic.trimmed }
        if mathRx.test(head) { meta.math = true }
    }
    if meta.courseName.isEmpty { meta.courseName = headerName }
    if lecture.unitPrefix == nil, let top = prefixes.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) { meta.unitPrefix = top.key }
    if meta.courseName.isEmpty, let claude = (try? fs.readString("\(course)/AGENTS.md")) ?? (try? fs.readString("\(course)/CLAUDE.md")), let m = Rx("\\*\\*([A-Z0-9]+)\\s*-\\s*([^*]+)\\*\\*").first(claude) {
        if lecture.code == nil { meta.code = m[1] ?? "" }
        meta.courseName = (m[2] ?? "").trimmed
    }
    let own = units.filter { $0.prefix == meta.unitPrefix }
    if own.contains(where: { $0.sep == "-" }) && !own.contains(where: { $0.sep == "" }) { meta.unitSep = "-" }
    meta.weeks = Array(Set(own.map(\.n))).sorted()
    return meta
}
