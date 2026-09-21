import Foundation

/// What the last publish sent, kept in the course folder (`.studio/published.json`) so it travels with the
/// repository: the account it went to, the remote course, when, and the hash of every file at that moment.
/// The course screen compares the files on disk against it to say which units changed since, but only while
/// that same account is connected: another account's page does not have these files.
public struct PublishRecord: Codable, Equatable, Sendable {
    /// The lecture.studio handle the publish went to; nil in records written before it was kept.
    public var handle: String?
    public var slug: String
    public var url: String
    public var at: String
    /// item id ("unit/path") to sha256
    public var files: [String: String]
    public init(handle: String? = nil, slug: String, url: String, at: String, files: [String: String]) { self.handle = handle; self.slug = slug; self.url = url; self.at = at; self.files = files }

    /// Does this record describe the connected account's page? A record without a handle belongs to nobody.
    public func belongs(to handle: String?) -> Bool {
        guard let mine = self.handle, let handle, !handle.isEmpty else { return false }
        return mine.lowercased() == handle.lowercased()
    }

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
