import Foundation
import WebKit
import UniformTypeIdentifiers
import StudioCore

/// `studio-app://bundle/<file>` serves the JS core and themes; `studio-app://repo/<path>` serves repo
/// files (deck assets, PDFs, sources to index). Same scheme, so the preview's fetches stay same-origin.
final class StudioSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "studio-app"
    var repo: () -> RepoFS?

    init(repo: @escaping () -> RepoFS?) {
        self.repo = repo
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { return fail(task, 400) }
        let rel = url.pathComponents.dropFirst().joined(separator: "/")
        var data: Data?
        switch host {
        case "bundle":
            let u = WebHost.resource(rel)
            if ProcessInfo.processInfo.environment["STUDIO_DEBUG"] != nil { FileHandle.standardError.write(Data("[bundle] \(Bundle.module.bundlePath) resourceURL=\(Bundle.module.resourceURL?.path ?? "nil") -> \(u.path)\n".utf8)) }
            data = try? Data(contentsOf: u)
        case "repo":
            if let fs = repo() { data = try? fs.readBytes(rel) }
        default:
            break
        }
        if ProcessInfo.processInfo.environment["STUDIO_DEBUG"] != nil { FileHandle.standardError.write(Data("[scheme] \(task.request.httpMethod ?? "GET") \(url) -> \(data?.count ?? -1) bytes\n".utf8)) }
        guard let data else { return fail(task, 404) }
        let mime = UTType(filenameExtension: (rel as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        if task.request.httpMethod?.uppercased() != "HEAD" { task.didReceive(data) }
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask, _ status: Int) {
        guard let url = task.request.url else { return }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"])!
        task.didReceive(resp)
        task.didFinish()
    }
}

/// Bridges `webkit.messageHandlers.<name>` to closures. One instance per web view.
final class BridgeHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    var onMessage: (String, Any) -> Void = { _, _ in }
    var onRequest: (String, Any) async -> Any? = { _, _ in nil }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage(message.name, message.body)
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        let name = message.name
        let body = message.body
        Task { @MainActor in
            let r = await onRequest(name, body)
            replyHandler(r, nil)
        }
    }
}

enum WebHost {
    static let schemeHandler = StudioSchemeHandler(repo: { nil })

    /// A file under the package's copied `Resources` folder, wherever SwiftPM put the bundle.
    static func resource(_ rel: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        for candidate in [base.appendingPathComponent("Resources/\(rel)"), base.appendingPathComponent(rel)] {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return base.appendingPathComponent("Resources/\(rel)")
    }

    static func configuration(bridge: BridgeHandler, replies: [String], messages: [String]) -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(schemeHandler, forURLScheme: StudioSchemeHandler.scheme)
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        for m in messages { cfg.userContentController.add(bridge, name: m) }
        for r in replies { cfg.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: r) }
        return cfg
    }

    /// A page that loads one bundle from the app's resources.
    static func page(script: String, body: String = "", style: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>\(style)</style>
        </head><body>\(body)<script src="studio-app://bundle/\(script)"></script></body></html>
        """
    }
}

/// Decode a JSON-like value from the bridge into a Codable.
func decodeBridge<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
    guard let value, JSONSerialization.isValidJSONObject(value), let d = try? JSONSerialization.data(withJSONObject: value) else { return nil }
    return try? JSONDecoder().decode(type, from: d)
}

func encodeBridge<T: Encodable>(_ value: T) -> Any {
    guard let d = try? JSONEncoder().encode(value), let obj = try? JSONSerialization.jsonObject(with: d) else { return [:] }
    return obj
}
