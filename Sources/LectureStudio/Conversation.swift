import Foundation
import UniformTypeIdentifiers

/// Conversation state that outlives the chat panel: panels hide and show while a turn streams.
/// Mirrors app/lib/client/chat-store.ts, with the stream events arriving from the agent bridge.
struct ChatAttachment: Codable, Equatable, Identifiable {
    var id: String?
    var kind: String
    var url: String
    var name: String?
    var mime_type: String?
    var isImage: Bool { kind == "image" || (name ?? "").range(of: "\\.(png|jpe?g|gif|webp|svg)$", options: [.regularExpression, .caseInsensitive]) != nil }
    private enum CodingKeys: String, CodingKey { case id, kind, url, name, mime_type }
}

struct ChatCitation: Codable, Equatable {
    var marker: Int?
    var kind: String?
    var title: String?
    var quote: String?
    var filename: String?
    var page: Int?
    var label: String { (title ?? filename ?? kind ?? "source") }
}

struct ChatTodo: Codable, Equatable, Identifiable {
    var id: String
    var content: String
    var status: String
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var content: String
    var events: [String] = []
    var attachments: [ChatAttachment] = []
    var citations: [ChatCitation] = []
    var error: String?
}

struct ApprovalRequest: Codable, Equatable {
    var tool_call_id: String
    var action: String
    var detail: String?
    var consequence: String?
    var tool: String?
    var summary: String?
}

struct QuestionOption: Codable, Equatable, Hashable {
    var label: String
    var description: String?
}

struct AgentQuestion: Codable, Equatable, Identifiable {
    var id: String
    var header: String
    var question: String
    var options: [QuestionOption]
    var multi_select: Bool
    var allow_other: Bool
}

struct PendingQuestions: Codable, Equatable {
    var tool_call_id: String
    var questions: [AgentQuestion]
}

@MainActor @Observable
final class Conversation {
    let key: String
    var messages: [ChatMessage] = []
    var todos: [ChatTodo] = []
    var sessionId: String?
    var running = false
    var approval: ApprovalRequest?
    var question: PendingQuestions?
    /// The id of the in-flight turn on the bridge.
    var turnId: String?

    init(key: String) {
        self.key = key
        sessionId = AppSettings.sessionId(for: key)
    }

    func patchLast(_ fn: (inout ChatMessage) -> Void) {
        guard !messages.isEmpty else { return }
        fn(&messages[messages.count - 1])
    }

    func reset() {
        AppSettings.setSessionId(nil, for: key)
        messages = []
        todos = []
        sessionId = nil
        approval = nil
        question = nil
    }
}

func summarize(_ v: Any?, max: Int = 120) -> String {
    guard let v else { return "" }
    let s: String
    if let str = v as? String { s = str } else if let d = try? JSONSerialization.data(withJSONObject: v, options: [.withoutEscapingSlashes]) { s = String(decoding: d, as: UTF8.self) } else { s = String(describing: v) }
    return s.count > max ? String(s.prefix(max - 1)) + "…" : s
}


/// A file the user attached to the next message. Sent as a data: URI; images are seen by the model,
/// other files are read as text by the platform.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var name: String { url.lastPathComponent }
    var mime: String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
    var isImage: Bool { mime.hasPrefix("image/") }
    static let maxBytes = 20 * 1024 * 1024

    /// The SDK attachment: {kind, url (data URI), name, mime_type}.
    func payload() throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        if data.count > Self.maxBytes { throw AgentError("\(name) is larger than 20 MB") }
        return ["kind": isImage ? "image" : "file", "url": "data:\(mime);base64,\(data.base64EncodedString())", "name": name, "mime_type": mime]
    }
}
