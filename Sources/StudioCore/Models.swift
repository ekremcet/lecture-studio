import Foundation

/// Who is presenting. Stored as `studio.json` at the root of the lecture repo.
public struct Profile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var affiliation: String?
    public var unit: String?
    public var email: String?
    public var contact: [String]?
    public var language: String?
    public var style: String?
    public var unitLabel: String?
    /// Top-level folders or files of the library that are neither courses nor talks (scripts, tooling); hidden from the studio.
    public var exclude: [String]?

    public init(name: String = "", affiliation: String? = nil, unit: String? = nil, email: String? = nil, contact: [String]? = nil, language: String? = nil, style: String? = nil, unitLabel: String? = nil, exclude: [String]? = nil) {
        self.name = name; self.affiliation = affiliation; self.unit = unit; self.email = email
        self.contact = contact; self.language = language; self.style = style; self.unitLabel = unitLabel; self.exclude = exclude
    }

    public static func empty() -> Profile { Profile(name: "", contact: [], language: "English", unitLabel: "week") }
}

public enum LectureKind: String, Codable, Sendable { case course, talk }

/// Per-lecture display metadata, `<course>/studio.json`.
public struct LectureMeta: Codable, Equatable, Sendable {
    public var title: String?
    public var code: String?
    public var term: String?
    public var kind: LectureKind?
    public var unitPrefix: String?
    public var language: String?
    /// Archived courses stay in the library but drop to the bottom of the picker; the agent leaves them alone.
    public var archived: Bool?
    /// The folder this term was copied from ("cs221-fall25"), for comparisons.
    public var derivedFrom: String?
    /// First lecture, ISO date (yyyy-MM-dd); unit dates count weekly from here.
    public var startDate: String?
    public init(title: String? = nil, code: String? = nil, term: String? = nil, kind: LectureKind? = nil, unitPrefix: String? = nil, language: String? = nil, archived: Bool? = nil, derivedFrom: String? = nil, startDate: String? = nil) {
        self.title = title; self.code = code; self.term = term; self.kind = kind; self.unitPrefix = unitPrefix; self.language = language
        self.archived = archived; self.derivedFrom = derivedFrom; self.startDate = startDate
    }
}

public enum FileKind: String, Codable, Sendable, CaseIterable { case deck, md, pdf, docx, xlsx, pptx, image, text, other }

public struct FileInfo: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var path: String
    public var course: String
    public var unit: String
    public var name: String
    public var kind: FileKind
    public var title: String
    public var size: Int
    /// Last modification, seconds since 1970.
    public var modified: Double
    public var id: String { path }
    public init(path: String, course: String, unit: String, name: String, kind: FileKind, title: String, size: Int, modified: Double = 0) {
        self.path = path; self.course = course; self.unit = unit; self.name = name; self.kind = kind; self.title = title; self.size = size; self.modified = modified
    }
}

public let TEXT_KINDS: Set<FileKind> = [.deck, .md, .text]

public enum SourceScope: String, Codable, Sendable, CaseIterable, Identifiable { case global, lecture, unit; public var id: String { rawValue } }

public struct DiskSource: Codable, Equatable, Hashable, Sendable {
    public var path: String
    public var name: String
    public var size: Int
    public var scope: SourceScope
}

public struct CourseMeta: Codable, Equatable, Sendable {
    public var code: String
    public var courseName: String
    public var math: Bool
    public var boldWeekFooter: Bool
    public var unitPrefix: String
    public var unitSep: String
    public var kind: LectureKind
    public var weeks: [Int]
    public var topics: [Int: String]
}

public struct GitChange: Codable, Equatable, Hashable, Sendable {
    public var status: String
    public var path: String
    public init(status: String, path: String) { self.status = status; self.path = path }
}

public struct GitCommitInfo: Codable, Equatable, Sendable {
    public var hash: String
    public var date: String
    public var subject: String
}

public struct GitStatus: Codable, Equatable, Sendable {
    public var root: String
    public var branch: String
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var changes: [GitChange]
    public var lastCommit: GitCommitInfo?
    public var fetchError: String?

    public init(root: String, branch: String, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, changes: [GitChange] = [], lastCommit: GitCommitInfo? = nil, fetchError: String? = nil) {
        self.root = root
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
        self.lastCommit = lastCommit
        self.fetchError = fetchError
    }

    /// Why Pull is off now, or nil when it can run.
    public var pullBlocker: String? {
        if upstream == nil { return "No upstream branch" }
        if !changes.isEmpty { return "Commit first, then pull" }
        return behind == 0 ? "Nothing to pull" : nil
    }

    /// Why Push is off now, or nil when it can run.
    public var pushBlocker: String? {
        if upstream == nil { return "No upstream branch" }
        if ahead == 0 { return changes.isEmpty ? "Nothing to push" : "Commit first, then push" }
        return nil
    }
}

/// The operations the git bar runs, one at a time.
public enum GitOp: String, CaseIterable, Sendable {
    case commit, push, pull

    public var title: String {
        switch self { case .commit: "Commit all"; case .push: "Push"; case .pull: "Pull" }
    }
    public var working: String {
        switch self { case .commit: "Committing…"; case .push: "Pushing…"; case .pull: "Pulling…" }
    }
    /// Whether the status should fetch again afterwards (a commit changes nothing on the remote).
    public var refetches: Bool { self != .commit }
}

/// JSON helpers shared by the small settings files of the repo.
enum StudioJSON {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
    static func encodePretty<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value)
    }
}
