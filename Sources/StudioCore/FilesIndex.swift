import Foundation

/// The repo listing the pickers and the workspace are built from.
public struct FilesIndex: Sendable {
    public var files: [FileInfo]
    public var lectures: [String: LectureMeta]
    /// Files in any `sources/` folder; the first-run checklist asks whether any exist.
    public var sources: Int

    static let skipDirs: Set<String> = ["node_modules", "assets", "sources", "sources-private", "site-mirror", "input_data", "venv", ".venv", "__pycache__", "dist", "build", "solutions-private"]
    static let textExt: Set<String> = ["txt", "py", "cpp", "c", "h", "hpp", "js", "jsx", "ts", "tsx", "css", "html", "yml", "yaml", "sql", "json", "csv", "xml", "sh", "mjs", "cjs", "toml", "ini", "tex", "r", "java", "kt", "go", "rs"]
    static let imageExt: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]
    static let frontMatter = Rx("^---\\r?\\n([\\s\\S]*?)\\r?\\n---")
    static let marpTrue = Rx("^marp:\\s*true\\s*$", .anchorsMatchLines)
    static let h1 = Rx("^#\\s+(.+)$", .anchorsMatchLines)
    static let footer = Rx("^footer:\\s*\"?([^\"\\n]*)\"?", .anchorsMatchLines)

    public static func kindOf(name: String, head: String?) -> FileKind {
        let ext = (name.split(separator: ".").last.map(String.init) ?? "").lowercased()
        if ext == "md" {
            if let head, let fm = frontMatter.first(head)?[1], marpTrue.test(fm) { return .deck }
            return .md
        }
        if ext == "pdf" { return .pdf }
        if ext == "docx" { return .docx }
        if ext == "xlsx" || ext == "xls" { return .xlsx }
        if ext == "pptx" { return .pptx }
        if imageExt.contains(ext) { return .image }
        if textExt.contains(ext) { return .text }
        return .other
    }

    /// Every file of the repo except assets and tooling directories, at most 4 levels deep.
    public static func scan(fs: RepoFS) -> FilesIndex {
        var out: [FileInfo] = []
        var sources = 0
        let fm = FileManager.default
        let excluded = Set(ProfileStore(fs: fs).read().exclude ?? [])

        func walk(_ rel: String, _ depth: Int) {
            let abs = rel.isEmpty ? fs.root : fs.root.appendingPathComponent(rel)
            guard let entries = try? fm.contentsOfDirectory(atPath: abs.path) else { return }
            for name in entries.sorted() {
                let full = abs.appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full.path, isDirectory: &isDir)
                if isDir.boolValue && name == "sources" {
                    if let inner = try? fm.contentsOfDirectory(atPath: full.path) {
                        sources += inner.filter { f in
                            var d: ObjCBool = false
                            return !f.hasPrefix(".") && fm.fileExists(atPath: full.appendingPathComponent(f).path, isDirectory: &d) && !d.boolValue
                        }.count
                    }
                    continue
                }
                if name.hasPrefix(".") || skipDirs.contains(name) { continue }
                if rel.isEmpty && excluded.contains(name) { continue }
                let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
                if isDir.boolValue {
                    if depth < 4 { walk(childRel, depth + 1) }
                    continue
                }
                if name.hasSuffix(".pyc") || name == "package-lock.json" || name == META_FILE { continue }
                let attrs = try? fm.attributesOfItem(atPath: full.path)
                let size = (attrs?[.size] as? Int) ?? 0
                let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                var head: String? = nil
                if name.hasSuffix(".md"), let text = try? String(contentsOf: full, encoding: .utf8) { head = String(text.prefix(4000)) }
                let kind = kindOf(name: name, head: head)
                var title = ""
                if let head {
                    let h = h1.first(head)?[1] ?? ""
                    let f = footer.first(head)?[1] ?? ""
                    let raw = kind == .deck ? (f.isEmpty ? h : f) : h
                    title = String(raw.replacingOccurrences(of: "**", with: "").prefix(80))
                }
                let segs = childRel.split(separator: "/").map(String.init)
                out.append(FileInfo(path: childRel, course: segs.count > 1 ? segs[0] : "(root)", unit: segs.count > 2 ? segs[1] : "", name: name, kind: kind, title: title, size: size, modified: modified))
            }
        }
        walk("", 0)
        out.sort { $0.path.compare($1.path, options: [.numeric]) == .orderedAscending }
        return FilesIndex(files: out, lectures: LectureMetaStore(fs: fs).all(), sources: sources)
    }
}

/// Source files on disk in the three folders the app knows.
public enum SourceFolders {
    public static let dir = "sources"

    static func list(fs: RepoFS, rel: String, scope: SourceScope) -> [DiskSource] {
        let abs = fs.root.appendingPathComponent(rel)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: abs.path) else { return [] }
        var out: [DiskSource] = []
        for name in entries where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: abs.appendingPathComponent(name).path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: abs.appendingPathComponent(name).path)[.size] as? Int) ?? 0
            out.append(DiskSource(path: "\(rel)/\(name)", name: name, size: size, scope: scope))
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// `sources/` at the root, `<course>/sources/`, `<course>/<unit>/sources/`.
    public static func sources(fs: RepoFS, course: String, unit: String) -> [DiskSource] {
        var out = list(fs: fs, rel: dir, scope: .global)
        if !course.isEmpty && course != "(root)" {
            out += list(fs: fs, rel: "\(course)/\(dir)", scope: .lecture)
            if !unit.isEmpty { out += list(fs: fs, rel: "\(course)/\(unit)/\(dir)", scope: .unit) }
        }
        return out
    }

    /// Store a source file in the repo: root `sources/` when the course is empty. Returns the repo path.
    public static func store(fs: RepoFS, course: String, unit: String, fileName: String, data: Data) throws -> String {
        if !course.isEmpty && course.contains("/") { throw RepoPathError("course must be one folder name") }
        if !unit.isEmpty && unit.contains("/") { throw RepoPathError("unit must be one folder name") }
        let base = fileName.split(separator: "/").last.map(String.init) ?? fileName
        let name = Rx("[^A-Za-z0-9._ -]").replace(base, with: "-")
        if data.count > 200 * 1024 * 1024 { throw RepoPathError("file larger than 200 MB") }
        let rel = course.isEmpty ? "\(dir)/\(name)" : "\(course)\(unit.isEmpty ? "" : "/\(unit)")/\(dir)/\(name)"
        try fs.writeBytes(rel, data, overwrite: true)
        return rel
    }

    /// Remove a source file. Only paths inside a `sources/` folder are accepted.
    public static func remove(fs: RepoFS, path: String) throws {
        guard Rx("(^|/)sources/[^/]+$").test(path) else { throw RepoPathError("only files inside a sources/ folder can be removed here") }
        try fs.remove(path)
    }
}
