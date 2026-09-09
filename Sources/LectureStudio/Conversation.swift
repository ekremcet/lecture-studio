import Foundation
import UniformTypeIdentifiers
import StudioCore

/// Conversation state that outlives the chat panel: panels hide and show while a turn streams.
/// The stream events arrive from the agent bridge.
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
    /// Identity in the archive: `New` starts another id, the history list opens an older one.
    var id = UUID()
    var created = Date()
    var updated = Date()
    var messages: [ChatMessage] = []
    var todos: [ChatTodo] = []
    var sessionId: String?
    var running = false
    var approval: ApprovalRequest?
    var question: PendingQuestions?
    /// The id of the in-flight turn on the bridge.
    var turnId: String?

    /// Stream patches wait here and land together (`flushInterval`), so a fast stream changes the
    /// observed `messages` a few times a second instead of once per token. Every token used to
    /// re-render and re-lay-out the whole transcript, which froze the app on a long reply (2026-09-09).
    @ObservationIgnored private var pending = PendingPatches<ChatMessage>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    static let flushInterval: Duration = .milliseconds(80)

    init(key: String) { self.key = key }

    var title: String { ArchivedChat.title(for: messages) }

    /// The conversation as the archive keeps it.
    func archived() -> ArchivedChat {
        ArchivedChat(id: id, scope: key, sessionId: sessionId, title: title, created: created, updated: updated, messages: messages)
    }

    /// Shows an archived conversation; its Oberik session continues from the next message.
    func restore(_ a: ArchivedChat) {
        flushTask?.cancel()
        flushTask = nil
        pending.clear()
        id = a.id
        created = a.created
        updated = a.updated
        sessionId = a.sessionId
        messages = a.messages
        todos = []
        approval = nil
        question = nil
    }

    /// Changes the last message. Patches queue in order and land on the next tick; `now` lands the
    /// queue at once, for events the rest of the UI reacts to (the end of the turn, an error).
    func patchLast(now: Bool = false, _ fn: @escaping (inout ChatMessage) -> Void) {
        pending.add(fn)
        if now { flushPatches() } else { scheduleFlush() }
    }

    /// Lands every queued patch as one change of `messages`.
    func flushPatches() {
        flushTask?.cancel()
        flushTask = nil
        guard !messages.isEmpty else { pending.clear(); return }
        var last = messages[messages.count - 1]
        if pending.drain(into: &last) { messages[messages.count - 1] = last }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard !Task.isCancelled else { return }
            self?.flushPatches()
        }
    }

    /// Starts a new conversation (the old one stays in the archive).
    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pending.clear()
        id = UUID()
        created = Date()
        updated = created
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
