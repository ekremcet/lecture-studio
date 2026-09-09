import Foundation

/// The two control-plane calls: mint an end-user token, list models.
/// The project key never leaves this process; the web view only ever sees short-lived tokens.
public struct OberikControl: Sendable {
    public static let defaultBaseURL = "https://oberik.com"
    /// The capabilities the session asks for. The project ceiling may trim them.
    public static let sessionCapabilities = ["chat", "steer", "computer", "web_search", "todo", "approvals", "ask_user", "ui_tools", "documents:read", "documents:write", "input:file", "input:image", "output:file"]

    public let projectId: String
    public let projectKey: String
    public let baseURL: String

    public init(projectId: String, projectKey: String, baseURL: String = OberikControl.defaultBaseURL) {
        self.projectId = projectId
        self.projectKey = projectKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    public struct APIError: LocalizedError {
        public let status: Int
        public let message: String
        public var errorDescription: String? { "\(message) (HTTP \(status))" }
    }

    func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Any {
        guard let url = URL(string: "\(baseURL)/api/projects/\(projectId)\(path)") else { throw APIError(status: 0, message: "bad URL") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue(projectKey, forHTTPHeaderField: "X-API-Key")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        if !(200..<300).contains(status) {
            let d = json as? [String: Any]
            throw APIError(status: status, message: (d?["detail"] as? String) ?? (d?["message"] as? String) ?? "HTTP \(status)")
        }
        return json ?? [:]
    }

    public struct Token: Sendable {
        public var accessToken: String
        public var expiresAt: Date
        public var capabilities: [String]
        public var warnings: [String]
    }

    public func mint(subject: String, expiresIn: Int = 3600) async throws -> Token {
        let r = try await request("POST", "/token", body: ["subject": subject, "capabilities": Self.sessionCapabilities, "expiresIn": expiresIn]) as? [String: Any] ?? [:]
        guard let token = r["access_token"] as? String else { throw APIError(status: 0, message: "mint returned no access_token") }
        let exp = (r["expires_in"] as? Double) ?? Double(expiresIn)
        return Token(accessToken: token, expiresAt: Date().addingTimeInterval(exp), capabilities: r["capabilities"] as? [String] ?? [], warnings: r["warnings"] as? [String] ?? [])
    }

    public struct Model: Identifiable, Equatable, Sendable {
        public var id: String
        public var provider: String
        public var input: [String]
    }

    public struct Models: Sendable {
        public var models: [Model]
        public var defaultModel: String?
        public var tiersMode: String?
        public var tierSimple: String?
        public var tierNormal: String?
    }

    /// The chat models registered on the project, and the default.
    public func models() async throws -> Models {
        async let providersJ = request("GET", "/providers")
        async let defaultJ = request("GET", "/default-model")
        async let tiersJ = request("GET", "/model-tiers")
        let providers = try await providersJ as? [[String: Any]] ?? []
        let def = try await defaultJ as? [String: Any] ?? [:]
        let tiers = (try? await tiersJ) as? [String: Any] ?? [:]
        var models: [Model] = []
        for p in providers {
            let facts = p["modelFacts"] as? [String: [String: Any]] ?? [:]
            let label = (p["label"] as? String) ?? (p["provider"] as? String) ?? ""
            for m in p["models"] as? [String] ?? [] {
                let f = facts[m]
                if ((f?["mode"] as? String) ?? "chat") != "chat" { continue }
                models.append(Model(id: m, provider: label, input: f?["input"] as? [String] ?? ["text"]))
            }
        }
        return Models(models: models, defaultModel: def["defaultModel"] as? String, tiersMode: tiers["mode"] as? String, tierSimple: tiers["simple"] as? String, tierNormal: tiers["normal"] as? String)
    }
}

/// `.env` at the project root, for a one-click import into the app's settings during development.
public enum DotEnv {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmed
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eq]).trimmed
            var v = String(line[line.index(after: eq)...]).trimmed
            if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
            out[k] = v
        }
        return out
    }
}
