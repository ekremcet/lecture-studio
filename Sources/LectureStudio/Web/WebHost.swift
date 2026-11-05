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

/// The app's web views. When a web view is first responder, WebKit reports every ⌘-key as handled by
/// the page, so the menu bar never sees ⌘Q, ⌘H, ⌘, or ⌘S: the app cannot be quit from the editor.
/// Offer ⌘-keys to the menu bar first. The Edit menu's own items stay with the page, so CodeMirror
/// keeps its own undo, copy, paste and select-all; its Find submenu goes to the menu bar like the rest.
final class StudioWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), window?.firstResponder === self, let items = NSApp.mainMenu?.items {
            for item in items {
                guard let menu = item.submenu else { continue }
                let menus = Self.isEditMenu(menu) ? menu.items.compactMap(\.submenu) : [menu]
                if menus.contains(where: { $0.performKeyEquivalent(with: event) }) { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func isEditMenu(_ menu: NSMenu) -> Bool {
        menu.items.contains { $0.action == Selector(("undo:")) || $0.action == Selector(("copy:")) }
    }
}

/// Keeps the preview page in its web view. A click on a link in a deck or document used to load the
/// link into the shared preview web view itself, which replaced the preview page with no way back to
/// it. Web and mail links now open in the default browser, links to repo files (a linked PDF, say)
/// open in their own app, and links to a heading on the same page still scroll there.
@MainActor
final class ExternalLinkPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = ExternalLinkPolicy()

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, action.targetFrame?.isMainFrame ?? true else { return .allow }
        // The app's own page load (loadHTMLString) and script-driven work stay in the view.
        guard action.navigationType == .linkActivated || action.navigationType == .formSubmitted || !Self.isOwn(url) else {
            return .allow
        }
        if Self.isSamePage(url, webView.url) { return .allow }
        Self.openOutside(url)
        return .cancel
    }

    /// `target="_blank"` and `window.open`: never open a second web view, hand the link out instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { Self.openOutside(url) }
        return nil
    }

    private static func isOwn(_ url: URL) -> Bool {
        ["studio-app", "about", "data", "blob"].contains(url.scheme?.lowercased() ?? "")
    }

    /// Only the fragment differs: an in-page anchor such as a table-of-contents link.
    private static func isSamePage(_ a: URL, _ b: URL?) -> Bool {
        guard let b, a.fragment != nil else { return false }
        func strip(_ u: URL) -> String { u.absoluteString.components(separatedBy: "#")[0] }
        return strip(a) == strip(b)
    }

    private static func openOutside(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == StudioSchemeHandler.scheme {
            // studio-app://repo/<path>: a file in the course repo; open it in the app that owns it.
            guard url.host == "repo", let fs = WebHost.schemeHandler.repo() else { return }
            let rel = url.pathComponents.dropFirst().joined(separator: "/")
            if let file = try? fs.resolve(rel) { NSWorkspace.shared.open(file) }
            return
        }
        guard ["http", "https", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
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
