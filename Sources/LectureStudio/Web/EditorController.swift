import Foundation
import WebKit
import StudioCore

/// What the find bar over the editor shows. The search itself runs in CodeMirror.
@MainActor @Observable
final class EditorFind {
    var shown = false
    var replacing = false
    var text = ""
    var replacement = ""
    var caseSensitive = false
    var wholeWord = false
    var regexp = false
    var status = FindStatus()
    /// Bumped to put the keyboard in the find field.
    var focusRequest = 0

    var label: String { status.label(query: text) }
}

/// The CodeMirror editor. Swift pushes text and hears edits, the top line, ⌘S, and find results.
@MainActor
final class EditorController: NSObject {
    let webView: WKWebView
    let find = EditorFind()
    private let bridge = BridgeHandler()
    private var ready = false
    private var pending: [() -> Void] = []

    var onChange: (String) -> Void = { _ in }
    var onLine: (Int, String) -> Void = { _, _ in }
    var onSave: () -> Void = {}
    /// "Add to chat" on a selection: the text and its 1-based first and last line.
    var onAddToChat: (String, Int, Int) -> Void = { _, _, _ in }

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
            case "find":
                self.find.status = FindStatus(count: d["count"] as? Int ?? 0, current: d["current"] as? Int ?? 0, invalid: d["invalid"] as? Bool ?? false, capped: d["capped"] as? Bool ?? false)
            case "findClose": self.closeFind(focusEditor: true)
            case "addToChat": self.onAddToChat(d["text"] as? String ?? "", d["from"] as? Int ?? 1, d["to"] as? Int ?? 1)
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

    /// Run a call and wait for its answer; nil until the page has loaded.
    private func value(_ js: String, _ args: [String: Any] = [:]) async -> Any? {
        guard ready else { return nil }
        return try? await webView.callAsyncJavaScript(js, arguments: args, contentWorld: .page)
    }

    // MARK: find and replace

    /// Open the find bar (with the replace row if asked), seeded with the selection when it is short.
    func showFind(replace: Bool) async {
        if let sel = await value("return window.studioEditor.selectionForFind()") as? String, !sel.isEmpty { find.text = sel }
        find.shown = true
        find.replacing = replace
        find.focusRequest += 1
        updateFind()
    }

    /// Search again after the query or an option changed.
    func updateFind() {
        guard find.shown else { return }
        run("window.studioEditor.find(spec)", ["spec": findSpec])
    }

    private var findSpec: [String: Any] {
        ["search": find.text, "replace": find.replacement, "caseSensitive": find.caseSensitive, "regexp": find.regexp, "wholeWord": find.wholeWord]
    }

    func findNext(backwards: Bool = false) {
        guard find.shown, !find.text.isEmpty else { return }
        run("window.studioEditor.findNext(backwards)", ["backwards": backwards])
    }

    func replaceNext() {
        guard find.shown, !find.text.isEmpty else { return }
        // The query goes along, so a replacement typed a moment ago is the one used.
        run("window.studioEditor.find(spec); window.studioEditor.replaceNext()", ["spec": findSpec])
    }

    /// Replace every match in one undoable edit. Answers how many were replaced.
    func replaceAll() async -> Int {
        guard find.shown, !find.text.isEmpty else { return 0 }
        return await value("window.studioEditor.find(spec); return window.studioEditor.replaceAll()", ["spec": findSpec]) as? Int ?? 0
    }

    func closeFind(focusEditor: Bool) {
        guard find.shown else { return }
        find.shown = false
        run("window.studioEditor.endFind(focus)", ["focus": focusEditor])
        if focusEditor { webView.window?.makeFirstResponder(webView) }
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
