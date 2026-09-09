import Foundation

/// The reasons a repo operation refuses. The messages are stable, so the agent's tool
/// results read the same on both platforms.
public struct RepoPathError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A file that must exist but does not (`ENOENT`), or must not exist but does (`EEXIST`).
public enum RepoFileError: LocalizedError, Equatable {
    case missing(String)
    case exists(String)
    public var errorDescription: String? {
        switch self {
        case .missing(let p): return "\(p): no such file"
        case .exists(let p): return "\(p): already exists"
        }
    }
}

public struct DirEntry: Codable, Equatable, Sendable {
    public var name: String
    public var kind: String // "file" | "dir"
    public var size: Int?
}

/// File-system access confined to the lecture repo. Every write of the app and of the agent's tools
/// goes through here.
public struct RepoFS: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Resolve a repo-relative path and refuse anything that escapes the repo or enters .git.
    public func resolve(_ relative: String) throws -> URL {
        let rootPath = root.path
        let abs = root.appendingPathComponent(relative).standardizedFileURL.path
        if abs != rootPath && !abs.hasPrefix(rootPath + "/") {
            throw RepoPathError("path escapes the lecture repo: \(relative)")
        }
        if abs.split(separator: "/").contains(".git") {
            throw RepoPathError("path inside .git is refused: \(relative)")
        }
        return URL(fileURLWithPath: abs)
    }

    public func exists(_ relative: String) -> Bool {
        guard let u = try? resolve(relative) else { return false }
        return FileManager.default.fileExists(atPath: u.path)
    }

    public func isDirectory(_ relative: String) -> Bool {
        guard let u = try? resolve(relative) else { return false }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &dir) && dir.boolValue
    }

    public func listDir(_ relative: String = ".") throws -> [DirEntry] {
        let dir = try resolve(relative)
        let fm = FileManager.default
        var out: [DirEntry] = []
        for name in try fm.contentsOfDirectory(atPath: dir.path) {
            if name.hasPrefix(".") { continue }
            let p = dir.appendingPathComponent(name).path
            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)
            if isDir.boolValue {
                out.append(DirEntry(name: name, kind: "dir", size: nil))
            } else {
                let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int) ?? 0
                out.append(DirEntry(name: name, kind: "file", size: size))
            }
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public struct TextRange: Codable, Equatable, Sendable {
        public var text: String
        public var lines: Int
        public var from: Int
        public var to: Int
    }

    /// Read a text file, optionally a 1-based inclusive line range.
    public func readText(_ relative: String, from: Int? = nil, to: Int? = nil) throws -> TextRange {
        let all = try readString(relative).jsLines
        let start = max(1, from ?? 1)
        let end = min(all.count, to ?? all.count)
        let slice = start <= end ? Array(all[(start - 1)..<end]).joined(separator: "\n") : ""
        return TextRange(text: slice, lines: all.count, from: start, to: end)
    }

    public func readString(_ relative: String) throws -> String {
        let u = try resolve(relative)
        guard FileManager.default.fileExists(atPath: u.path) else { throw RepoFileError.missing(relative) }
        return try String(contentsOf: u, encoding: .utf8)
    }

    public func readBytes(_ relative: String) throws -> Data {
        let u = try resolve(relative)
        guard FileManager.default.fileExists(atPath: u.path) else { throw RepoFileError.missing(relative) }
        return try Data(contentsOf: u)
    }

    private func ensureParent(_ u: URL) throws {
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: try resolve(relative), withIntermediateDirectories: true)
    }

    /// Create a new file; refuses when it exists.
    public func createText(_ relative: String, _ content: String) throws {
        let u = try resolve(relative)
        if FileManager.default.fileExists(atPath: u.path) { throw RepoFileError.exists(relative) }
        try ensureParent(u)
        try content.write(to: u, atomically: true, encoding: .utf8)
    }

    public func overwriteText(_ relative: String, _ content: String) throws {
        let u = try resolve(relative)
        try ensureParent(u)
        try content.write(to: u, atomically: true, encoding: .utf8)
    }

    public func appendText(_ relative: String, _ content: String) throws {
        let u = try resolve(relative)
        guard FileManager.default.fileExists(atPath: u.path) else { throw RepoFileError.missing(relative) }
        let h = try FileHandle(forWritingTo: u)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(content.utf8))
    }

    /// Replace exactly one occurrence. Refuses zero or many matches.
    @discardableResult
    public func replaceOnce(_ relative: String, old: String, new: String) throws -> Int {
        let text = try readString(relative)
        guard let first = text.range(of: old) else { throw RepoPathError("old text not found") }
        if text.range(of: old, range: text.index(after: first.lowerBound)..<text.endIndex) != nil {
            throw RepoPathError("old text matches more than once; include more context")
        }
        let line = String(text[..<first.lowerBound]).jsLines.count
        try overwriteText(relative, text.replacingCharacters(in: first, with: new))
        return line
    }

    public func writeBytes(_ relative: String, _ data: Data, overwrite: Bool = false) throws {
        let u = try resolve(relative)
        if !overwrite && FileManager.default.fileExists(atPath: u.path) { throw RepoFileError.exists(relative) }
        try ensureParent(u)
        try data.write(to: u, options: .atomic)
    }

    public func remove(_ relative: String) throws {
        try FileManager.default.removeItem(at: try resolve(relative))
    }

    public func rename(_ from: String, to: String) throws {
        try FileManager.default.moveItem(at: try resolve(from), to: try resolve(to))
    }
}
