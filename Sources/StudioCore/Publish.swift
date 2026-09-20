import Foundation

/// What a course publishes to lecture.studio: the deck of every unit as Marp Markdown with its theme and
/// assets, the exported PDF next to it, the syllabus, and whatever else the lecturer ticks. Instructor
/// material is never offered; the platform refuses it too. Pure: the sheet builds the plan, the client ships it.
public enum PublishKind: String, Codable, Sendable { case deck, pdf, asset, theme, doc }

public struct PublishItem: Identifiable, Equatable, Sendable {
    /// Unit number, nil for course-level files.
    public var unit: Int?
    /// Path on the platform, relative to the unit or the course: "week3-slides.md", "assets/fig.png".
    public var path: String
    /// Where the bytes are: a repo-relative path, or an absolute file URL for a bundled theme.
    public var source: Source
    public var kind: PublishKind
    public var size: Int
    public var selected: Bool
    public var id: String { "\(unit ?? 0)/\(path)" }
    public enum Source: Equatable, Sendable { case repo(String), file(URL) }
    public init(unit: Int?, path: String, source: Source, kind: PublishKind, size: Int, selected: Bool) {
        self.unit = unit; self.path = path; self.source = source; self.kind = kind; self.size = size; self.selected = selected
    }
}

public struct PublishPlan: Equatable, Sendable {
    public var slug: String
    public var code: String?
    public var title: String
    public var term: String?
    public var startDate: String?
    public var weekCount: Int
    public var cancelledDates: [String]
    public var unitLabel: String
    public var topics: [Int: String]
    public var items: [PublishItem]
    /// Files left out because their names look like instructor material.
    public var heldBack: [String]
    public var selectedBytes: Int { items.filter(\.selected).reduce(0) { $0 + $1.size } }
}

public enum Publish {
    /// The platform's own rule, mirrored: these never leave the Mac.
    static let privatePatterns: [NSRegularExpression] = [
        "instructor[-_ ]?guide", "solution", "^sources/", "^archive/", "^research/", "^scripts/", "^claude\\.md$", "^agents\\.md$", "^studio\\.json$", "(^|/)\\.",
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    public static func looksPrivate(_ path: String) -> Bool {
        let r = NSRange(path.startIndex..., in: path)
        return privatePatterns.contains { $0.firstMatch(in: path, range: r) != nil }
    }

    /// Instructor material worth telling the lecturer about; config files and dotfiles are skipped silently.
    static let tellPatterns = [try! NSRegularExpression(pattern: "instructor[-_ ]?guide|solution", options: [.caseInsensitive])]
    static func worthTelling(_ name: String) -> Bool {
        let r = NSRange(name.startIndex..., in: name)
        return tellPatterns.contains { $0.firstMatch(in: name, range: r) != nil }
    }

    /// The remote slug for a course folder: lowercase letters, digits and dashes.
    public static func slug(for folder: String) -> String {
        let s = folder.lowercased().replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(s.prefix(60))
    }

    public static let maxBytes = 40 * 1024 * 1024

    static let frontMatter = try! NSRegularExpression(pattern: "^---\\s*\\n([\\s\\S]*?)\\n---", options: [])
    static let marpTrue = try! NSRegularExpression(pattern: "^marp:\\s*true\\s*$", options: [.anchorsMatchLines])
    static let themeLine = try! NSRegularExpression(pattern: "^theme:\\s*[\"']?([A-Za-z0-9_.-]+)[\"']?\\s*$", options: [.anchorsMatchLines])

    /// Is this Marp markdown, and which theme does it name?
    public static func deckHead(_ text: String) -> (marp: Bool, theme: String?) {
        let head = String(text.prefix(4000))
        guard let fm = frontMatter.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)), let r = Range(fm.range(at: 1), in: head) else { return (false, nil) }
        let block = String(head[r])
        let marp = marpTrue.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) != nil
        var theme: String? = nil
        if let t = themeLine.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)), let tr = Range(t.range(at: 1), in: block) { theme = String(block[tr]) }
        return (marp, theme)
    }

    /// Extra calendar fields the studio.json may carry beyond LectureMeta.
    struct Calendar: Decodable { var weekCount: Int?; var cancelledDates: [String]? }

    /// Build the plan for a course folder. `themeDirs` are searched, in order, for `<theme>.css`.
    public static func plan(fs: RepoFS, course: String, meta: LectureMeta, courseMeta: CourseMeta, themeDirs: [URL]) -> PublishPlan {
        var items: [PublishItem] = []
        var heldBack: [String] = []
        var themes = Set<String>()
        let imageExt: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]
        let docExt: Set<String> = ["md", "pdf", "docx", "xlsx", "pptx", "txt", "ipynb", "zip"]

        func add(_ item: PublishItem) { if !items.contains(where: { $0.id == item.id }) { items.append(item) } }

        for n in courseMeta.weeks {
            let folder = "\(courseMeta.unitPrefix)\(courseMeta.unitSep)\(n)"
            guard let entries = try? fs.listDir("\(course)/\(folder)") else { continue }
            for e in entries where e.kind == "file" {
                let rel = "\(course)/\(folder)/\(e.name)"
                if looksPrivate(e.name) { if worthTelling(e.name) { heldBack.append("\(folder)/\(e.name)") }; continue }
                let ext = (e.name as NSString).pathExtension.lowercased()
                let size = e.size ?? 0
                if ext == "md" {
                    let head = (try? fs.readText(rel, from: 1, to: 60).text) ?? ""
                    let d = deckHead(head)
                    if d.marp {
                        add(PublishItem(unit: n, path: e.name, source: .repo(rel), kind: .deck, size: size, selected: true))
                        if let t = d.theme { themes.insert(t) }
                    } else {
                        add(PublishItem(unit: n, path: e.name, source: .repo(rel), kind: .doc, size: size, selected: false))
                    }
                } else if ext == "pdf" {
                    add(PublishItem(unit: n, path: e.name, source: .repo(rel), kind: .pdf, size: size, selected: true))
                } else if docExt.contains(ext) {
                    add(PublishItem(unit: n, path: e.name, source: .repo(rel), kind: .doc, size: size, selected: false))
                } else if imageExt.contains(ext) {
                    add(PublishItem(unit: n, path: "assets/\(e.name)", source: .repo(rel), kind: .asset, size: size, selected: true))
                }
            }
            if let assets = try? fs.listDir("\(course)/\(folder)/assets") {
                for e in assets where e.kind == "file" && !e.name.hasPrefix(".") {
                    let ext = (e.name as NSString).pathExtension.lowercased()
                    guard imageExt.contains(ext) || docExt.contains(ext) else { continue }
                    add(PublishItem(unit: n, path: "assets/\(e.name)", source: .repo("\(course)/\(folder)/assets/\(e.name)"), kind: imageExt.contains(ext) ? .asset : .doc, size: e.size ?? 0, selected: imageExt.contains(ext)))
                }
            }
        }

        // Course level: the syllabus is ticked, other documents are offered.
        if let entries = try? fs.listDir(course) {
            for e in entries where e.kind == "file" {
                if looksPrivate(e.name) { if worthTelling(e.name) { heldBack.append(e.name) }; continue }
                let ext = (e.name as NSString).pathExtension.lowercased()
                guard docExt.contains(ext) else { continue }
                let isSyllabus = e.name.lowercased().hasPrefix("syllabus")
                var kind: PublishKind = ext == "pdf" ? .pdf : .doc
                if ext == "md", isSyllabus == false, let head = try? fs.readText("\(course)/\(e.name)", from: 1, to: 60).text, deckHead(head).marp { kind = .deck }
                add(PublishItem(unit: nil, path: e.name, source: .repo("\(course)/\(e.name)"), kind: kind, size: e.size ?? 0, selected: isSyllabus))
            }
        }

        // Themes the decks name: the course's own themes folder first, then the bundled ones.
        for t in themes.sorted() {
            let inRepo = "\(course)/themes/\(t).css"
            if fs.exists(inRepo), let url = try? fs.resolve(inRepo), let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) {
                add(PublishItem(unit: nil, path: "themes/\(t).css", source: .repo(inRepo), kind: .theme, size: size, selected: true)); continue
            }
            for dir in themeDirs {
                let url = dir.appendingPathComponent("\(t).css")
                if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                    add(PublishItem(unit: nil, path: "themes/\(t).css", source: .file(url), kind: .theme, size: size, selected: true)); break
                }
            }
        }

        var weekCount = courseMeta.weeks.max() ?? 0
        var cancelled: [String] = []
        if let data = try? fs.readBytes("\(course)/studio.json"), let c = try? JSONDecoder().decode(Calendar.self, from: data) {
            if let w = c.weekCount, w >= weekCount { weekCount = w }
            cancelled = c.cancelledDates ?? []
        }
        for i in items.indices where items[i].size > maxBytes { items[i].selected = false }

        return PublishPlan(
            slug: slug(for: course), code: Labels.courseCode(course, meta).isEmpty ? nil : Labels.courseCode(course, meta), title: Labels.courseTitle(course, meta),
            term: meta.term, startDate: meta.startDate, weekCount: max(1, min(30, weekCount)), cancelledDates: cancelled,
            unitLabel: courseMeta.unitPrefix.prefix(1).uppercased() + courseMeta.unitPrefix.dropFirst(), topics: courseMeta.topics,
            items: items.sorted { ($0.unit ?? 0, $0.kind.rawValue, $0.path) < ($1.unit ?? 0, $1.kind.rawValue, $1.path) }, heldBack: heldBack.sorted())
    }
}
