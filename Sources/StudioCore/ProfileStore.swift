import Foundation

public let META_FILE = "studio.json"

/// The presenter profile at the repo root. Mirrors app/lib/server/profile.ts.
public struct ProfileStore {
    public let fs: RepoFS
    public init(fs: RepoFS) { self.fs = fs }

    public func exists() -> Bool { fs.exists(META_FILE) }

    public func read() -> Profile {
        guard let data = try? fs.readBytes(META_FILE), let raw = try? StudioJSON.decode(Profile.self, from: data) else { return .empty() }
        return Self.clean(raw)
    }

    @discardableResult
    public func write(_ p: Profile) throws -> Profile {
        let clean = Self.clean(p)
        try fs.overwriteText(META_FILE, String(decoding: try StudioJSON.encodePretty(clean), as: UTF8.self) + "\n")
        return clean
    }

    /// A starting point when the repo has no profile yet: the git identity of the machine.
    public func suggested() async -> Profile {
        var p = Profile.empty()
        let git = GitClient(root: fs.root)
        if let n = try? await git.run(["config", "user.name"]) { p.name = n.trimmed }
        if let e = try? await git.run(["config", "user.email"]) { p.email = e.trimmed }
        return p
    }

    public static func clean(_ p: Profile) -> Profile {
        func s(_ v: String?) -> String { (v ?? "").trimmed }
        var out = Profile(name: s(p.name))
        if !s(p.affiliation).isEmpty { out.affiliation = s(p.affiliation) }
        if !s(p.unit).isEmpty { out.unit = s(p.unit) }
        if !s(p.email).isEmpty { out.email = s(p.email) }
        let contact = (p.contact ?? []).map { $0.trimmed }.filter { !$0.isEmpty }
        if !contact.isEmpty { out.contact = contact }
        out.language = s(p.language).isEmpty ? "English" : s(p.language)
        if !s(p.style).isEmpty { out.style = s(p.style) }
        let label = Rx("[^a-z]").replace(s(p.unitLabel).lowercased(), with: "")
        out.unitLabel = label.isEmpty ? "week" : label
        let ex = (p.exclude ?? []).map { $0.trimmed }.filter { !$0.isEmpty }
        if !ex.isEmpty { out.exclude = Array(Set(ex)).sorted() }
        return out
    }

    /// Hide or show a top-level folder or file of the library.
    public func setExcluded(_ name: String, _ excluded: Bool) throws {
        var p = read()
        var ex = Set(p.exclude ?? [])
        if excluded { ex.insert(name) } else { ex.remove(name) }
        p.exclude = ex.isEmpty ? nil : ex.sorted()
        try write(p)
    }

    /// One line for the agent context.
    public static func summary(_ p: Profile) -> String {
        if p.name.isEmpty { return "" }
        let who = [p.name, p.affiliation, p.unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let lang = (p.language ?? "").isEmpty ? "" : " Default language: \(p.language!)."
        return "Presenter: \(who).\(lang) Full profile in studio.json at the repo root."
    }
}

/// `<course>/studio.json`. Mirrors app/lib/server/lecture-meta.ts.
public struct LectureMetaStore {
    public let fs: RepoFS
    public init(fs: RepoFS) { self.fs = fs }

    public func read(_ course: String) -> LectureMeta {
        guard let data = try? fs.readBytes("\(course)/\(META_FILE)"), let m = try? StudioJSON.decode(LectureMeta.self, from: data) else { return LectureMeta() }
        return m
    }

    public func write(_ course: String, _ meta: LectureMeta) throws {
        var clean = LectureMeta()
        if let t = meta.title?.trimmed, !t.isEmpty { clean.title = t }
        if let c = meta.code?.trimmed, !c.isEmpty { clean.code = c.uppercased() }
        if let t = meta.term?.trimmed, !t.isEmpty { clean.term = t }
        clean.kind = meta.kind
        let prefix = Rx("[^a-z]").replace((meta.unitPrefix ?? "").trimmed.lowercased(), with: "")
        if !prefix.isEmpty { clean.unitPrefix = prefix }
        if let l = meta.language?.trimmed, !l.isEmpty { clean.language = l }
        if meta.archived == true { clean.archived = true }
        if let d = meta.derivedFrom?.trimmed, !d.isEmpty { clean.derivedFrom = d }
        if let sd = meta.startDate?.trimmed, !sd.isEmpty { clean.startDate = sd }
        try fs.overwriteText("\(course)/\(META_FILE)", String(decoding: try StudioJSON.encodePretty(clean), as: UTF8.self) + "\n")
    }

    /// Every course folder with its metadata.
    public func all() -> [String: LectureMeta] {
        var out: [String: LectureMeta] = [:]
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: fs.root.path) else { return out }
        for name in entries where !name.hasPrefix(".") && name != "node_modules" && fs.isDirectory(name) {
            if let data = try? fs.readBytes("\(name)/\(META_FILE)"), let m = try? StudioJSON.decode(LectureMeta.self, from: data) { out[name] = m }
        }
        return out
    }
}
