import Foundation
import WebKit
import StudioCore

/// One Oberik document as the sources sheet needs it.
struct OberikDocument: Codable, Equatable, Identifiable {
    var id: String
    var filename: String
    var tags: [String]
    var status: String
    var error: String?
}

struct AgentError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// The Oberik SDK runs in a hidden web view. Swift mints tokens, answers tool calls, and receives the
/// stream events; the conversation state lives in `Conversation`. The project key never enters the page.
@MainActor
final class AgentBridge: NSObject {
    let webView: WKWebView
    private let bridge = BridgeHandler()
    private var ready = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var token: OberikControl.Token?
    private var loaded = false

    /// Called for every chat event: (turn id, event name, payload).
    var onChat: (String, String, [String: Any]) -> Void = { _, _, _ in }
    /// `show_preview` and other UI tools.
    var onUi: (String, [String: Any]) -> Void = { _, _ in }
    /// The client tools. Return a JSON-serialisable result or throw.
    var toolHandler: (String, [String: Any]) async throws -> Any = { name, _ in throw AgentError("no handler for \(name)") }

    /// The origin the page claims. It must be on the project's allow-list (scripts/oberik-setup.ts adds the dev origins).
    static let origin = URL(string: "http://127.0.0.1:3005/")!

    override init() {
        let cfg = WebHost.configuration(bridge: bridge, replies: ["token", "tool"], messages: ["studio"])
        webView = StudioWebView(frame: .zero, configuration: cfg)
        super.init()
        bridge.onMessage = { [weak self] _, body in
            guard let self, let d = body as? [String: Any], let type = d["type"] as? String else { return }
            AgentBridge.debug("event \(type) \(d["event"] ?? "") \(d["kind"] ?? "") \(d["name"] ?? "") \(String(describing: d["message"] ?? "").prefix(200))")
            switch type {
            case "ready":
                self.ready = true
                let w = self.waiters
                self.waiters = []
                for c in w { c.resume() }
            case "chat":
                self.onChat(d["id"] as? String ?? "", d["event"] as? String ?? "", d)
            case "ui":
                self.onUi(d["name"] as? String ?? "", d["args"] as? [String: Any] ?? [:])
            case "log":
                AgentBridge.debug("js \(d["level"] ?? "") \(d["message"] ?? "")")
            default: break
            }
        }
        bridge.onRequest = { [weak self] name, body in
            guard let self else { return ["error": "bridge gone"] }
            AgentBridge.debug("request \(name) \(String(describing: (body as? [String: Any])?["name"] ?? ""))")
            switch name {
            case "token":
                let expired = (body as? [String: Any])?["expired"] as? Bool ?? false
                do { return ["token": try await self.accessToken(force: expired)] } catch { return ["error": error.localizedDescription] }
            case "tool":
                let d = body as? [String: Any] ?? [:]
                let toolName = d["name"] as? String ?? ""
                let args = d["args"] as? [String: Any] ?? [:]
                do {
                    let r = try await self.toolHandler(toolName, args)
                    return ["ok": true, "result": r]
                } catch {
                    return ["error": error.localizedDescription]
                }
            default:
                return nil
            }
        }
    }

    static let debugEnabled = ProcessInfo.processInfo.environment["STUDIO_DEBUG"] != nil
    static func debug(_ s: @autoclosure () -> String) {
        if debugEnabled { FileHandle.standardError.write(Data("[agent] \(s())\n".utf8)) }
    }

    /// Load the page once the credentials exist; a reload picks up changed settings.
    func load() {
        loaded = true
        ready = false
        token = nil
        webView.loadHTMLString(WebHost.page(script: "studio-agent.js"), baseURL: Self.origin)
    }

    private func whenReady() async {
        if !loaded { load() }
        if ready { return }
        await withCheckedContinuation { c in waiters.append(c) }
    }

    func accessToken(force: Bool) async throws -> String {
        if !force, let t = token, t.expiresAt.timeIntervalSinceNow > 90 { return t.accessToken }
        guard AppSettings.hasOberik else { throw AgentError("Oberik project id and key are not set. Open Settings.") }
        let control = OberikControl(projectId: AppSettings.projectId, projectKey: AppSettings.projectKey)
        let t = try await control.mint(subject: AppSettings.subject)
        AgentBridge.debug("token capabilities \(t.capabilities) warnings \(t.warnings)")
        token = t
        return t.accessToken
    }

    private func call(_ js: String, _ args: [String: Any] = [:]) async throws -> Any? {
        await whenReady()
        do {
            return try await webView.callAsyncJavaScript(js, arguments: args, contentWorld: .page)
        } catch {
            // WebKit wraps JS exceptions; surface the message the SDK threw.
            let ns = error as NSError
            let msg = (ns.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? ns.localizedDescription
            throw AgentError(msg)
        }
    }

    func send(id: String, message: String, context: String, sessionId: String?, model: String, tags: [String], attachments: [[String: Any]] = []) async throws {
        var input: [String: Any] = ["message": message, "context": context, "tags": tags]
        if let sessionId { input["session_id"] = sessionId }
        if !model.isEmpty { input["model"] = model }
        if !attachments.isEmpty { input["attachments"] = attachments }
        _ = try await call("window.studioAgent.send(id, input)", ["id": id, "input": input])
    }

    func cancel(id: String) async {
        _ = try? await call("await window.studioAgent.cancel(id)", ["id": id])
    }

    /// A message into the running turn. False when the turn had ended first (or the page lost it).
    func steer(id: String, message: String) async -> Bool {
        do {
            let r = try await call("return await window.studioAgent.steer(id, message)", ["id": id, "message": message])
            AgentBridge.debug("steer -> \(String(describing: r))")
            return r as? Bool ?? false
        } catch {
            AgentBridge.debug("steer failed: \(error.localizedDescription)")
            return false
        }
    }

    func resolveApproval(_ toolCallId: String, approved: Bool) async {
        _ = try? await call("window.studioAgent.resolveApproval(id, ok)", ["id": toolCallId, "ok": approved])
    }

    func answerQuestion(_ toolCallId: String, answer: [String: Any]) async {
        _ = try? await call("window.studioAgent.answerQuestion(id, answer)", ["id": toolCallId, "answer": answer])
    }

    func listDocuments(tags: [String]) async throws -> [OberikDocument] {
        let r = try await call("return await window.studioAgent.documents.list(tags)", ["tags": tags])
        return decodeBridge([OberikDocument].self, r) ?? []
    }

    func uploadDocument(repoPath: String, name: String, tags: [String]) async throws {
        _ = try await call("return await window.studioAgent.documents.upload(path, name, tags)", ["path": repoPath, "name": name, "tags": tags])
    }

    func deleteDocument(_ id: String) async throws {
        _ = try await call("await window.studioAgent.documents.delete(id)", ["id": id])
    }

    func reingestDocument(_ id: String) async throws {
        _ = try await call("await window.studioAgent.documents.reingest(id)", ["id": id])
    }

    func ping() async throws -> String {
        (try await call("return await window.studioAgent.ping()")) as? String ?? ""
    }
}
