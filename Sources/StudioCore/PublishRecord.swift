import Foundation

/// What the last publish sent, kept in the course folder (`.studio/published.json`) so it travels with the
/// repository: the remote course, when, and the hash of every file at that moment. The course screen compares
/// the files on disk against it to say which units changed since.
public struct PublishRecord: Codable, Equatable, Sendable {
    public var slug: String
    public var url: String
    public var at: String
    /// item id ("unit/path") to sha256
    public var files: [String: String]
    public init(slug: String, url: String, at: String, files: [String: String]) { self.slug = slug; self.url = url; self.at = at; self.files = files }

    public static let file = ".studio/published.json"
    public static func path(course: String) -> String { "\(course)/\(file)" }

    public static func read(fs: RepoFS, course: String) -> PublishRecord? {
        guard let data = try? fs.readBytes(path(course: course)) else { return nil }
        return try? JSONDecoder().decode(PublishRecord.self, from: data)
    }
    public func write(fs: RepoFS, course: String) throws {
        try fs.mkdir("\(course)/.studio")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fs.writeBytes(PublishRecord.path(course: course), try enc.encode(self), overwrite: true)
    }
}

/// A unit's standing against the last publish.
public enum PublishState: String, Sendable { case never, published, changed }

public enum PublishStatus {
    /// Compare a plan's ticked items (hashed on disk) against the record, unit by unit. Course-level items
    /// count under unit 0. A unit with any item missing from the record or with another hash is `changed`.
    public static func states(plan: PublishPlan, record: PublishRecord?, hash: (PublishItem) -> String?) -> [Int: PublishState] {
        var out: [Int: PublishState] = [:]
        guard let record else {
            for item in plan.items where item.selected { out[item.unit ?? 0] = .never }
            return out
        }
        for item in plan.items where item.selected {
            let unit = item.unit ?? 0
            if out[unit] == .changed { continue }
            guard let remote = record.files[item.id] else { out[unit] = out[unit] == nil && !record.files.keys.contains { $0.hasPrefix("\(unit)/") } ? .never : .changed; continue }
            if hash(item) == remote { if out[unit] == nil { out[unit] = .published } } else { out[unit] = .changed }
        }
        return out
    }
}
