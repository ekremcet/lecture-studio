import Foundation
import CryptoKit

/// The chat's messages and what hangs off them, as the bridge delivers them and as the archive keeps them.
public struct ChatAttachment: Codable, Equatable, Identifiable {
    public var id: String?
    public var kind: String
    public var url: String
    public var name: String?
    public var mime_type: String?
    public init(id: String? = nil, kind: String, url: String, name: String? = nil, mime_type: String? = nil) {
        self.id = id; self.kind = kind; self.url = url; self.name = name; self.mime_type = mime_type
    }
    public var isImage: Bool { kind == "image" || (name ?? "").range(of: "\\.(png|jpe?g|gif|webp|svg)$", options: [.regularExpression, .caseInsensitive]) != nil }
    private enum CodingKeys: String, CodingKey { case id, kind, url, name, mime_type }
}

public struct ChatCitation: Codable, Equatable {
    public var marker: Int?
    public var kind: String?
    public var title: String?
    public var quote: String?
    public var filename: String?
    public var page: Int?
    public init(marker: Int? = nil, kind: String? = nil, title: String? = nil, quote: String? = nil, filename: String? = nil, page: Int? = nil) {
        self.marker = marker; self.kind = kind; self.title = title; self.quote = quote; self.filename = filename; self.page = page
    }
    public var label: String { (title ?? filename ?? kind ?? "source") }
}

public struct ChatTodo: Codable, Equatable, Identifiable {
    public var id: String
    public var content: String
    public var status: String
    public init(id: String, content: String, status: String) { self.id = id; self.content = content; self.status = status }
}

public struct ChatMessage: Codable, Identifiable, Equatable {
    public enum Role: String, Codable { case user, assistant }
    public var id = UUID()
    public var role: Role
    public var content: String
    public var events: [String] = []
    public var attachments: [ChatAttachment] = []
    public var citations: [ChatCitation] = []
    public var error: String?
    /// A user message sent into a running turn (steering); shown where it landed, before the reply.
    public var steering = false
    public init(role: Role, content: String) { self.role = role; self.content = content }

    private enum CodingKeys: String, CodingKey { case id, role, content, events, attachments, citations, error, steering }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        events = try c.decodeIfPresent([String].self, forKey: .events) ?? []
        attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        citations = try c.decodeIfPresent([ChatCitation].self, forKey: .citations) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
        steering = try c.decodeIfPresent(Bool.self, forKey: .steering) ?? false
    }
}

/// One conversation as the archive stores it: a scope (a course, or a unit of a course), the Oberik
/// session that continues it, and the messages so far.
public struct ArchivedChat: Codable, Equatable, Identifiable {
    public var id: UUID
    public var scope: String
    public var sessionId: String?
    public var title: String
    public var created: Date
    public var updated: Date
    public var messages: [ChatMessage]
    public init(id: UUID, scope: String, sessionId: String?, title: String, created: Date, updated: Date, messages: [ChatMessage]) {
        self.id = id; self.scope = scope; self.sessionId = sessionId; self.title = title; self.created = created; self.updated = updated; self.messages = messages
    }

    /// The first line of the first thing the user asked, cut to fit a list row.
    public static func title(for messages: [ChatMessage]) -> String {
        guard let first = messages.first(where: { $0.role == .user })?.content else { return "" }
        let line = first.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count > 72 ? String(t.prefix(71)) + "…" : t
    }
}

/// What the history list shows without reading every message of every conversation.
public struct ChatSummary: Codable, Equatable, Identifiable {
    public var id: UUID
    public var scope: String
    public var sessionId: String?
    public var title: String
    public var created: Date
    public var updated: Date
    public var messageCount: Int
}

/// Conversations on disk, one JSON file each, under `<root>/<scope>/<id>.json`. The root is per library
/// folder (see `forRepo`), and the scope is the chat's key (a course, or `course/unit`), so every course
/// and every unit keeps its own history.
public final class ChatArchive {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// The archive of one library folder, under Application Support (`base` overrides that for tests):
    /// the folder's name plus a hash of its path, so two libraries with the same name stay apart.
    public static func forRepo(_ repoRoot: URL, base: URL? = nil) -> ChatArchive {
        let path = repoRoot.standardizedFileURL.path
        let hash = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let name = repoRoot.lastPathComponent.isEmpty ? "library" : repoRoot.lastPathComponent
        let b = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LectureStudio", isDirectory: true).appendingPathComponent("chats", isDirectory: true)
        return ChatArchive(root: b.appendingPathComponent("\(name)-\(hash)", isDirectory: true))
    }

    /// The folder of one scope. Keys hold `/` (course/unit); an empty key is the library root.
    public func folder(scope: String) -> URL {
        let safe = scope.isEmpty ? "_" : scope.replacingOccurrences(of: "/", with: "__")
        return root.appendingPathComponent(safe, isDirectory: true)
    }

    private func file(scope: String, id: UUID) -> URL { folder(scope: scope).appendingPathComponent("\(id.uuidString).json") }

    // Seconds since 1970 as a double: ISO 8601 would drop the fraction, and two conversations saved
    // within a second would then tie in the list.
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()

    /// Writes the whole conversation; the file also carries the message count for `list`.
    public func save(_ chat: ArchivedChat) throws {
        try FileManager.default.createDirectory(at: folder(scope: chat.scope), withIntermediateDirectories: true)
        var obj = try JSONSerialization.jsonObject(with: Self.encoder.encode(chat)) as? [String: Any] ?? [:]
        obj["messageCount"] = chat.messages.count
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try data.write(to: file(scope: chat.scope, id: chat.id), options: .atomic)
    }

    public func load(scope: String, id: UUID) -> ArchivedChat? {
        guard let d = try? Data(contentsOf: file(scope: scope, id: id)) else { return nil }
        return try? Self.decoder.decode(ArchivedChat.self, from: d)
    }

    /// The conversations of one scope, newest first.
    public func list(scope: String) -> [ChatSummary] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder(scope: scope).path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { n -> ChatSummary? in
            guard let d = try? Data(contentsOf: folder(scope: scope).appendingPathComponent(n)) else { return nil }
            return try? Self.decoder.decode(ChatSummary.self, from: d)
        }.sorted { ($0.updated, $0.created) > ($1.updated, $1.created) }
    }

    /// The most recent conversation of a scope, the one the chat shows when the scope opens.
    public func latest(scope: String) -> ArchivedChat? {
        guard let s = list(scope: scope).first else { return nil }
        return load(scope: scope, id: s.id)
    }

    public func delete(scope: String, id: UUID) throws {
        let f = file(scope: scope, id: id)
        if FileManager.default.fileExists(atPath: f.path) { try FileManager.default.removeItem(at: f) }
    }
}
