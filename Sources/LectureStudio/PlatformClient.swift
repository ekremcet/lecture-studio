import Foundation
import CryptoKit
import StudioCore

/// The lecture.studio API, as the Mac app uses it: a personal token from lecture.studio/settings, JSON in
/// and out, one multipart upload per file. Errors carry the server's own sentence.
struct PlatformClient: Sendable {
    var origin: URL
    var token: String

    struct Me: Decodable, Sendable { var handle: String; var name: String?; var url: String; var courses: [Course] }
    struct Course: Decodable, Sendable, Identifiable {
        var slug: String; var code: String?; var title: String; var term: String?; var visibility: String; var start_date: String?; var week_count: Int; var url: String
        var id: String { slug }
    }
    struct Ensure: Encodable, Sendable { var slug: String; var code: String?; var title: String; var term: String?; var description: String?; var start_date: String?; var week_count: Int; var cancelled_dates: [String]; var visibility: String?; var unit_label: String? }
    struct Ensured: Decodable, Sendable { var created: Bool; var slug: String; var url: String; var visibility: String }
    struct RemoteFile: Decodable, Sendable { var week: Int?; var path: String; var sha256: String; var size: Int; var kind: String; var visibility: String }
    struct Uploaded: Decodable, Sendable { var path: String; var week: Int?; var sha256: String; var replaced: Bool; var url: String }
    struct CourseDetails: Decodable, Sendable { var slug: String; var title: String; var visibility: String; var joins_locked: Bool; var join_url: String?; var students: Int; var url: String }
    struct SettingsPatch: Encodable, Sendable { var visibility: String?; var joins_locked: Bool?; var rotate_join_link: Bool? }

    private struct ErrorBody: Decodable { var error: String }
    private struct FilesBody: Decodable { var files: [RemoteFile] }
    private struct OkBody: Decodable { var ok: Bool }

    struct Failure: LocalizedError, Sendable {
        var status: Int
        var message: String
        var errorDescription: String? { message }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 600
        return URLSession(configuration: c)
    }()

    func me() async throws -> Me { try await get("api/me") }

    func ensure(_ e: Ensure) async throws -> Ensured {
        try await send("api/courses", method: "POST", body: try JSONEncoder().encode(e), contentType: "application/json")
    }

    func course(_ slug: String) async throws -> CourseDetails { try await get("api/courses/\(slug)") }

    func settings(_ slug: String, _ patch: SettingsPatch) async throws -> CourseDetails {
        try await send("api/courses/\(slug)/settings", method: "POST", body: try JSONEncoder().encode(patch), contentType: "application/json")
    }

    func files(_ slug: String) async throws -> [RemoteFile] {
        try await (get("api/courses/\(slug)/files") as FilesBody).files
    }

    func setWeek(_ slug: String, _ n: Int, topic: String?) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["topic": topic ?? ""])
        _ = try await send("api/courses/\(slug)/weeks/\(n)", method: "POST", body: body, contentType: "application/json") as OkBody
    }

    func upload(_ slug: String, week: Int?, path: String, name: String, data: Data, topic: String?) async throws -> Uploaded {
        let boundary = "ls-" + UUID().uuidString
        var body = Data()
        func field(_ k: String, _ v: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        if let week { field("week", String(week)) }
        field("path", path)
        if let topic, !topic.isEmpty { field("topic", topic) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name.replacingOccurrences(of: "\"", with: ""))\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return try await send("api/courses/\(slug)/files", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    // MARK: transport

    private func request(_ path: String, method: String) -> URLRequest {
        var r = URLRequest(url: origin.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("LectureStudio/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (macOS)", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(path, method: "GET"))
    }

    private func send<T: Decodable>(_ path: String, method: String, body: Data, contentType: String) async throws -> T {
        var r = request(path, method: method)
        r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return try await perform(r)
    }

    private func perform<T: Decodable>(_ r: URLRequest) async throws -> T {
        let (data, resp) = try await Self.session.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 303 || status == 302 || status == 401 { throw Failure(status: status, message: "The lecture.studio token is not valid. Create a new one on lecture.studio/settings and paste it in Settings › Publish.") }
        if !(200..<300).contains(status) {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "lecture.studio answered \(status)."
            throw Failure(status: status, message: msg)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw Failure(status: status, message: "Unexpected answer from lecture.studio (\(error.localizedDescription)).")
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
