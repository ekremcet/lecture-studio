import Foundation

/// Turn a title into a folder name; Turkish letters fold to ASCII.
public func slug(_ s: String) -> String {
    var t = s.decomposedStringWithCanonicalMapping
    t = Rx("[\\u0300-\\u036f]").replace(t, with: "")
    let map: [String: String] = ["ı": "i", "İ": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g", "ç": "c", "Ç": "c", "ö": "o", "Ö": "o", "ü": "u", "Ü": "u"]
    for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
    t = t.lowercased()
    t = Rx("[^a-z0-9]+").replace(t, with: "-")
    t = Rx("^-+|-+$").replace(t, with: "")
    return t
}

func cleanPrefix(_ p: String?, fallback: String) -> String {
    let v = Rx("[^a-z]").replace((p ?? "").trimmed.lowercased(), with: "")
    return v.isEmpty ? fallback : v
}

/// The scaffolds of the create dialogs.
public struct Scaffold {
    public let fs: RepoFS
    public init(fs: RepoFS) { self.fs = fs }

    public struct Created: Equatable, Sendable {
        public var course: String = ""
        public var unit: String = ""
        public var deck: String = ""
        public var path: String = ""
        public var created: [String] = []
        public var renamed = false
    }

    /// The default folder name of a course: `<code>-<name>` slugged.
    public static func defaultFolder(code: String, name: String) -> String {
        let c = code.trimmed
        return c.isEmpty ? slug(name) : "\(slug(c))-\(slug(name))"
    }

    public static func checkFolderName(_ folder: String) throws {
        if folder.isEmpty { throw RepoPathError("folder name is required") }
        if !Rx("^[a-z0-9][a-z0-9._-]*$").test(folder) { throw RepoPathError("folder name: lowercase letters, digits, dots, dashes") }
    }

    /// A folder the user picked may already exist (empty, or with material but no studio.json yet).
    func claimFolder(_ folder: String, location: URL?) throws {
        if let location {
            // Outside the library: the course lives there, the library holds a link to it.
            let inside = try fs.resolve(folder)
            if location.standardizedFileURL.path.hasPrefix(fs.root.path + "/") {
                // Inside the library after all: nothing to link.
            } else if !fs.exists(folder) {
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: inside, withDestinationURL: location)
            }
        }
        if fs.exists(folder) {
            if fs.exists("\(folder)/\(META_FILE)") { throw RepoPathError("\(folder) is already a course or a talk") }
            return
        }
        try fs.mkdir(folder)
    }

    public func lecture(code: String, name: String, language: String?, semester: String?, unitPrefix: String?, withSyllabus: Bool, withContext: Bool, folder folderName: String? = nil, location: URL? = nil) throws -> Created {
        let profile = ProfileStore(fs: fs).read()
        let code = code.trimmed.uppercased()
        if !code.isEmpty && !Rx("^[A-Z0-9][A-Z0-9 ._-]{1,15}$").test(code) { throw RepoPathError("code: letters, digits, dots, dashes (for example YZM2031 or CS-101)") }
        if name.trimmed.isEmpty { throw RepoPathError("name is required") }
        let folder = (folderName ?? "").trimmed.isEmpty ? Self.defaultFolder(code: code, name: name) : folderName!.trimmed
        if folder.isEmpty { throw RepoPathError("name must contain a letter or a digit") }
        try Self.checkFolderName(folder)
        try claimFolder(folder, location: location)
        let prefix = cleanPrefix(unitPrefix, fallback: profile.unitLabel ?? "week")
        let lang = (language ?? "").trimmed.isEmpty ? (profile.language ?? "English") : language!.trimmed
        let input = Templates.LectureInput(code: code, name: name.trimmed, language: lang, semester: (semester ?? "").trimmed.isEmpty ? "TBD" : semester!.trimmed, profile: profile, unitLabel: prefix)
        var out = Created(course: folder)
        if withSyllabus && !fs.exists("\(folder)/syllabus.md") {
            try fs.createText("\(folder)/syllabus.md", Templates.syllabus(input))
            out.created.append("\(folder)/syllabus.md")
        }
        if withContext && !fs.exists("\(folder)/AGENTS.md") {
            // AGENTS.md is the cross-agent convention; CLAUDE.md points at it for Claude Code.
            try fs.createText("\(folder)/AGENTS.md", Templates.courseContext(input, folder: folder))
            if !fs.exists("\(folder)/CLAUDE.md") { try fs.createText("\(folder)/CLAUDE.md", "@AGENTS.md\n") }
            out.created.append("\(folder)/AGENTS.md")
        }
        try LectureMetaStore(fs: fs).write(folder, LectureMeta(title: input.name, code: code, term: input.semester, kind: .course, unitPrefix: prefix, language: lang))
        return out
    }

    /// Bring an existing folder (a course with its decks) or a single deck file into the library.
    /// Copies by default; `move` relocates it. Writes `studio.json` so the studio shows it right away.
    public func importCourse(from source: URL, folder: String, title: String, code: String?, kind: LectureKind, move: Bool) throws -> Created {
        try Self.checkFolderName(folder)
        if fs.exists(folder) { throw RepoFileError.exists(folder) }
        let target = try fs.resolve(folder)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir) else { throw RepoFileError.missing(source.path) }
        if isDir.boolValue {
            if target.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") { throw RepoPathError("the library is inside the folder you chose; pick a folder outside it") }
            if move { try FileManager.default.moveItem(at: source, to: target) } else { try FileManager.default.copyItem(at: source, to: target) }
        } else {
            // A single deck: it becomes a talk folder with the deck named after the folder.
            try fs.mkdir("\(folder)/assets")
            try fs.mkdir("\(folder)/sources")
            let ext = source.pathExtension.isEmpty ? "md" : source.pathExtension
            let dest = target.appendingPathComponent("\(folder).\(ext)")
            if move { try FileManager.default.moveItem(at: source, to: dest) } else { try FileManager.default.copyItem(at: source, to: dest) }
            // Assets next to the deck come along, so relative images keep working.
            let sideAssets = source.deletingLastPathComponent().appendingPathComponent("assets")
            if FileManager.default.fileExists(atPath: sideAssets.path) {
                try? FileManager.default.removeItem(at: target.appendingPathComponent("assets"))
                try? FileManager.default.copyItem(at: sideAssets, to: target.appendingPathComponent("assets"))
            }
        }
        var meta = LectureMetaStore(fs: fs).read(folder)
        if !title.trimmed.isEmpty { meta.title = title.trimmed }
        if let c = code?.trimmed, !c.isEmpty { meta.code = c.uppercased() }
        meta.kind = kind
        if kind == .course && meta.unitPrefix == nil {
            let detected = courseMeta(fs: fs, course: folder)
            if !detected.weeks.isEmpty { meta.unitPrefix = detected.unitPrefix }
        }
        try LectureMetaStore(fs: fs).write(folder, meta)
        return Created(course: folder, created: [folder])
    }

    public func talk(name: String, event: String?, date: String?, language: String?, folder folderName: String? = nil, location: URL? = nil) throws -> Created {
        let profile = ProfileStore(fs: fs).read()
        if name.trimmed.isEmpty { throw RepoPathError("title is required") }
        let folder = (folderName ?? "").trimmed.isEmpty ? slug(name) : folderName!.trimmed
        if folder.isEmpty { throw RepoPathError("title must contain a letter or a digit") }
        try Self.checkFolderName(folder)
        try claimFolder(folder, location: location)
        try fs.mkdir("\(folder)/assets")
        try fs.mkdir("\(folder)/sources")
        let deck = "\(folder)/\(folder).md"
        if fs.exists(deck) { throw RepoFileError.exists(deck) }
        let ev = (event ?? "").trimmed
        try fs.createText(deck, Templates.talk(.init(title: name.trimmed, event: ev.isEmpty ? nil : ev, date: date, profile: profile)))
        try LectureMetaStore(fs: fs).write(folder, LectureMeta(title: name.trimmed, term: ev, kind: .talk, language: (language ?? "").trimmed.isEmpty ? profile.language : language!.trimmed))
        return Created(course: folder, deck: deck, created: [deck])
    }

    public func editLecture(course: String, title: String, code: String?, term: String?, newFolder: String?, unitPrefix: String?, kind: LectureKind?, newLocation: URL? = nil) async throws -> Created {
        if !fs.exists(course) { throw RepoFileError.missing(course) }
        var current = course
        var target = (newFolder ?? "").trimmed
        if let loc = newLocation, !loc.standardizedFileURL.path.hasPrefix(fs.root.path + "/") {
            // Moved out of the library: the files go there, the library keeps a link under the same name.
            let name = target.isEmpty ? course : target
            try Self.checkFolderName(name)
            let src = try fs.resolve(course)
            if FileManager.default.fileExists(atPath: loc.path) {
                let inside = (try? FileManager.default.contentsOfDirectory(atPath: loc.path))?.filter { !$0.hasPrefix(".") } ?? []
                if !inside.isEmpty { throw RepoPathError("\(loc.lastPathComponent) is not empty; choose or create an empty folder") }
                try FileManager.default.removeItem(at: loc)
            }
            try FileManager.default.createDirectory(at: loc.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: src, to: loc)
            if name != course, fs.exists(name) { throw RepoFileError.exists(name) }
            try FileManager.default.createSymbolicLink(at: try fs.resolve(name), withDestinationURL: loc)
            current = name
            target = ""
        }
        if !target.isEmpty && target != course {
            if !Rx("^[a-z0-9][a-z0-9._-]*$").test(target) { throw RepoPathError("folder name: lowercase letters, digits, dots, dashes") }
            if fs.exists(target) { throw RepoFileError.exists(target) }
            let git = GitClient(root: fs.root)
            if await git.isTracked(course) { try await git.move(course, target) } else { try fs.rename(course, to: target) }
            current = target
        }
        let store = LectureMetaStore(fs: fs)
        var prev = store.read(current)
        prev.title = title
        prev.code = code == "" ? nil : (code ?? prev.code)
        prev.term = term ?? prev.term
        prev.unitPrefix = unitPrefix ?? prev.unitPrefix
        prev.kind = kind ?? prev.kind
        try store.write(current, prev)
        var out = Created(course: current)
        out.renamed = current != course
        return out
    }

    public func week(course: String, week: Int, topic: String, withGuide: Bool, date: String? = nil) throws -> Created {
        if week < 1 || week > 99 { throw RepoPathError("the unit number must be between 1 and 99") }
        if topic.trimmed.isEmpty { throw RepoPathError("topic is required") }
        let profile = ProfileStore(fs: fs).read()
        let meta = courseMeta(fs: fs, course: course)
        let unit = "\(meta.unitPrefix)\(meta.unitSep)\(week)"
        let deckPath = "\(course)/\(unit)/\(unit)-slides.md"
        if fs.exists(deckPath) { throw RepoFileError.exists(deckPath) }
        try fs.mkdir("\(course)/\(unit)/assets")
        try fs.createText(deckPath, Templates.deck(.init(
            code: meta.code, courseName: meta.courseName.isEmpty ? course : meta.courseName, week: week, topic: topic.trimmed, date: date,
            math: meta.math, boldWeekFooter: meta.boldWeekFooter, previousTopic: meta.topics[week - 1], profile: profile, unitLabel: meta.unitPrefix)))
        var out = Created(course: course, unit: unit, deck: deckPath, created: [deckPath])
        if withGuide {
            let guide = "\(course)/\(unit)/\(unit)-instructor-guide.md"
            try fs.createText(guide, Templates.guide(week: week, topic: topic.trimmed, unitLabel: meta.unitPrefix))
            out.created.append(guide)
        }
        return out
    }

    public func file(course: String, unit: String, name: String, kind: String, title: String?) throws -> Created {
        var n = Rx("[\\\\/]").replace(name.trimmed, with: "-")
        if n.isEmpty { throw RepoPathError("name is required") }
        if !n.hasSuffix(".md") { n += ".md" }
        let rel = unit.isEmpty ? "\(course)/\(n)" : "\(course)/\(unit)/\(n)"
        let t = (title ?? "").trimmed
        var content = "# \(t.isEmpty ? String(n.dropLast(3)) : t)\n\n"
        if kind == "deck" {
            let profile = ProfileStore(fs: fs).read()
            let meta = courseMeta(fs: fs, course: course)
            let num = Int(Rx("(\\d+)$").first(unit)?[1] ?? "") ?? 1
            content = meta.kind == .talk
                ? Templates.talk(.init(title: t.isEmpty ? (meta.courseName.isEmpty ? course : meta.courseName) : t, profile: profile))
                : Templates.deck(.init(code: meta.code, courseName: meta.courseName.isEmpty ? course : meta.courseName, week: num, topic: t.isEmpty ? "Topic" : t, math: meta.math, boldWeekFooter: meta.boldWeekFooter, profile: profile, unitLabel: meta.unitPrefix))
        }
        try fs.createText(rel, content)
        return Created(course: course, unit: unit, path: rel, created: [rel])
    }
}

/// `save_asset`: an image from an https URL or a data: URI into `<week_dir>/assets/`.
public enum Assets {
    static let maxBytes = 20 * 1024 * 1024
    static let imageExt = Rx("\\.(png|jpe?g|gif|webp|svg|avif)$", .caseInsensitive)

    public struct Saved: Codable, Equatable, Sendable {
        public var ok = true
        public var path: String
        public var bytes: Int
        public var mime: String
        public var markdown: String
    }

    public static func fetch(_ source: String) async throws -> (Data, String) {
        if source.hasPrefix("data:") {
            guard let m = Rx("^data:([^;,]+)?(;base64)?,([\\s\\S]*)$").first(source) else { throw RepoPathError("malformed data URI") }
            let payload = m[3] ?? ""
            let bytes: Data
            if m[2] != nil {
                guard let d = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { throw RepoPathError("malformed data URI") }
                bytes = d
            } else {
                bytes = Data((payload.removingPercentEncoding ?? payload).utf8)
            }
            if bytes.count > maxBytes { throw RepoPathError("asset larger than 20 MB") }
            return (bytes, m[1] ?? "application/octet-stream")
        }
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { throw RepoPathError("only http(s) or data: sources") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("marp-lecture-studio/0.1", forHTTPHeaderField: "user-agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) { throw RepoPathError("download failed: \(http.statusCode)") }
        if data.count > maxBytes { throw RepoPathError("asset larger than 20 MB") }
        return (data, http?.value(forHTTPHeaderField: "content-type") ?? "application/octet-stream")
    }

    public static func save(fs: RepoFS, weekDir: String, filename: String, source: String, overwrite: Bool = false) async throws -> Saved {
        if weekDir.isEmpty || filename.isEmpty || source.isEmpty { throw RepoPathError("week_dir, filename and source are required") }
        let base = filename.split(separator: "/").last.map(String.init) ?? filename
        let name = Rx("[^A-Za-z0-9._-]").replace(base, with: "-")
        if !imageExt.test(name) { throw RepoPathError("filename must end with an image extension") }
        let (bytes, mime) = try await fetch(source)
        if !mime.hasPrefix("image/") && !source.hasPrefix("data:") && mime != "application/octet-stream" { throw RepoPathError("not an image: \(mime)") }
        let dir = Rx("/+$").replace(weekDir, with: "")
        let rel = "\(dir)/assets/\(name)"
        try fs.writeBytes(rel, bytes, overwrite: overwrite)
        return Saved(path: rel, bytes: bytes.count, mime: mime, markdown: "![bg right contain](./assets/\(name))")
    }
}
