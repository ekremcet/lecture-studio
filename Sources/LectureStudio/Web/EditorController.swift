import Foundation
import WebKit

/// The CodeMirror editor. Swift pushes text and hears edits, the top line, and ⌘S.
@MainActor
final class EditorController: NSObject {
    let webView: WKWebView
    private let bridge = BridgeHandler()
    private var ready = false
    private var pending: [() -> Void] = []

    var onChange: (String) -> Void = { _ in }
    var onLine: (Int, String) -> Void = { _, _ in }
    var onSave: () -> Void = {}

    override init() {
        let cfg = WebHost.configuration(bridge: bridge, replies: [], messages: ["studio"])
        webView = StudioWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        bridge.onMessage = { [weak self] _, body in
            guard let self, let d = body as? [String: Any], let type = d["type"] as? String else { return }
            switch type {
            case "ready":
                self.ready = true
                let p = self.pending
                self.pending = []
                p.forEach { $0() }
            case "change": self.onChange(d["text"] as? String ?? "")
            case "line": self.onLine(d["line"] as? Int ?? 0, d["source"] as? String ?? "scroll")
            case "save": self.onSave()
            default: break
            }
        }
        let style = "html,body{margin:0;height:100%;background:transparent}.cm-editor{height:100vh}"
        webView.loadHTMLString(WebHost.page(script: "studio-editor.js", style: style), baseURL: URL(string: "studio-app://editor/"))
    }

    private func run(_ js: String, _ args: [String: Any]) {
        let call = { [weak self] in
            guard let self else { return }
            Task { _ = try? await self.webView.callAsyncJavaScript(js, arguments: args, contentWorld: .page) }
        }
        if ready { call() } else { pending.append(call) }
    }

    func setValue(_ text: String, plain: Bool) {
        run("window.studioEditor.setValue(text, kind)", ["text": text, "kind": plain ? "plain" : "markdown"])
    }

    func insertBlock(_ snippet: String) {
        run("window.studioEditor.insertBlock(snippet)", ["snippet": snippet])
    }

    func wrap(_ before: String, _ after: String, placeholder: String = "text") {
        run("window.studioEditor.wrap(before, after, placeholder)", ["before": before, "after": after, "placeholder": placeholder])
    }

    func setDark(_ dark: Bool) {
        run("window.studioEditor.setDark(dark)", ["dark": dark])
    }

    func scrollToLine(_ line: Int) {
        run("window.studioEditor.scrollToLine(line)", ["line": line])
    }
}
