import Foundation
import WebKit
import StudioCore

struct QaOffender: Codable, Equatable {
    var tag: String
    var text: String
    var rightOverflow: Int
    var bottomOverflow: Int
}

struct QaSlide: Codable, Equatable {
    var page: Int
    var title: String
    var characters: Int
    var words: Int
    var scrollOverflowX: Int
    var scrollOverflowY: Int
    var offenders: [QaOffender]
    var missingImages: [String]
    var warnings: [String]
}

struct QaResult: Codable, Equatable {
    var slides: [QaSlide]
    var overflowPages: [Int]
    var missingImagePages: [Int]

    /// The payload kept small for the model: only failing slides in detail.
    var compact: [String: Any] {
        let failing = slides.filter { !$0.offenders.isEmpty || !$0.missingImages.isEmpty || $0.scrollOverflowY > 2 }
        return [
            "slides": slides.count,
            "overflowPages": overflowPages,
            "missingImagePages": missingImagePages,
            "scopedStylePages": slides.filter { $0.warnings.contains("scoped style present") }.map(\.page),
            "details": failing.map { s -> [String: Any] in
                ["page": s.page, "title": s.title, "words": s.words, "scrollOverflowY": s.scrollOverflowY,
                 "offenders": s.offenders.prefix(5).map { ["tag": $0.tag, "text": $0.text, "rightOverflow": $0.rightOverflow, "bottomOverflow": $0.bottomOverflow] },
                 "missingImages": s.missingImages, "warnings": s.warnings]
            },
        ]
    }
}

/// The preview web view: the Marp render lives in the page; Swift asks for renders, scans and jumps.
@MainActor
final class PreviewController: NSObject {
    let webView: WKWebView
    private let bridge = BridgeHandler()
    private var ready = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var renderSeq = 0

    var onVisible: (Int) -> Void = { _ in }
    var onRendered: (Int, [Int]) -> Void = { _, _ in }
    var onError: (String) -> Void = { _ in }

    override init() {
        let cfg = WebHost.configuration(bridge: bridge, replies: [], messages: ["studio"])
        webView = StudioWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        bridge.onMessage = { [weak self] _, body in
            guard let self, let d = body as? [String: Any], let type = d["type"] as? String else { return }
            switch type {
            case "ready":
                // Themes first, then the waiting renders, so the first deck opens with its theme applied.
                Task {
                    await self.pushThemes()
                    self.ready = true
                    let w = self.waiters
                    self.waiters = []
                    for c in w { c.resume() }
                }
            case "visible": if let i = d["index"] as? Int { self.onVisible(i) }
            case "rendered": self.onRendered(d["slideCount"] as? Int ?? 0, d["starts"] as? [Int] ?? [0])
            case "error": self.onError(d["message"] as? String ?? "render failed")
            default: break
            }
        }
        let style = """
        html,body{margin:0;background:#4a4a4a}
        body{padding:12px 0 40px}
        body.doc{background:#fff;padding:0}
        #deck{width:100%}
        .marpit{display:flex;flex-direction:column;gap:14px;align-items:center;width:100%}
        .marpit > svg{display:block;box-shadow:0 2px 10px rgba(0,0,0,.4);background:#fff;scroll-margin-top:12px}
        .marpit > svg.qa-overflow{outline:8px solid #e5484d}
        .marpit > svg.qa-missing{outline:8px solid #f5a524}
        body.present{background:#000;padding:0;overflow:hidden;height:100vh}
        body.present .marpit{display:block;width:100vw;height:100vh}
        body.present .marpit > svg{box-shadow:none}
        .md-view{max-width:760px;margin:0 auto;padding:20px 28px 40px;color:#1f2937;font:14px/1.6 -apple-system,system-ui,sans-serif}
        .md-view pre{background:#f3f4f6;padding:10px 12px;border-radius:6px;overflow-x:auto;font-size:12px}
        .md-view code{font-family:ui-monospace,Menlo,monospace;font-size:12px}
        .md-view table{border-collapse:collapse}.md-view td,.md-view th{border:1px solid #d1d5db;padding:3px 8px}
        .md-view img{max-width:100%}.md-view blockquote{border-left:3px solid #d1d5db;margin:0;padding-left:12px;color:#6b7280}
        .md-view h1{font-size:24px}.md-view h2{font-size:19px;margin-top:24px}.md-view h3{font-size:16px}
        .md-view pre.plain{background:transparent;white-space:pre-wrap;padding:0}
        """
        webView.loadHTMLString(WebHost.page(script: "studio-preview.js", body: "<div id=\"deck\"></div>", style: style), baseURL: URL(string: "studio-app://preview/"))
    }

    private func whenReady() async {
        if ready { return }
        await withCheckedContinuation { c in waiters.append(c) }
    }

    private func pushThemes() async {
        var themes: [String: String] = [:]
        let dir = WebHost.resource("themes")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for f in files where f.hasSuffix(".css") {
                themes[String(f.dropLast(4))] = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            }
        }
        _ = try? await webView.callAsyncJavaScript("window.studioPreview.setThemes(themes)", arguments: ["themes": themes], contentWorld: .page)
    }

    /// Render the deck; returns the slide count and the 0-based start line of each slide.
    @discardableResult
    func render(markdown: String, deckDir: String) async -> (count: Int, starts: [Int]) {
        await whenReady()
        renderSeq += 1
        let seq = renderSeq
        do {
            let r = try await webView.callAsyncJavaScript("return window.studioPreview.render(markdown, deckDir)", arguments: ["markdown": markdown, "deckDir": deckDir], contentWorld: .page)
            guard seq == renderSeq, let d = r as? [String: Any] else { return (0, [0]) }
            return (d["slideCount"] as? Int ?? 0, d["starts"] as? [Int] ?? [0])
        } catch {
            onError(error.localizedDescription)
            return (0, [0])
        }
    }

    /// Render a plain markdown or text document instead of a deck.
    func renderDocument(markdown: String, deckDir: String, plain: Bool) async {
        await whenReady()
        _ = try? await webView.callAsyncJavaScript("return window.studioPreview.renderDocument(markdown, deckDir, plain)", arguments: ["markdown": markdown, "deckDir": deckDir, "plain": plain], contentWorld: .page)
    }

    func scan() async throws -> QaResult {
        await whenReady()
        let r = try await webView.callAsyncJavaScript("return await window.studioPreview.scan()", arguments: [:], contentWorld: .page)
        guard let q = decodeBridge(QaResult.self, r) else { throw RepoPathError("preview returned no QA result") }
        return q
    }

    /// Presenter mode: one slide (0-based) fills the page; -1 returns to the scrolling deck.
    func present(_ index: Int) {
        Task {
            await whenReady()
            _ = try? await webView.callAsyncJavaScript("window.studioPreview.present(index)", arguments: ["index": index], contentWorld: .page)
        }
    }

    func scrollTo(page: Int, smooth: Bool) {
        Task { _ = try? await webView.callAsyncJavaScript("window.studioPreview.scrollTo(page, smooth)", arguments: ["page": page, "smooth": smooth], contentWorld: .page) }
    }
}
