import Foundation
import AppKit
import StudioCore

/// Development aid: `STUDIO_SMOKE=/dir` walks the screens against the open repo without clicking,
/// and writes what it saw. `STUDIO_SMOKE_CHAT=1` adds one read-only agent turn.
@MainActor
enum Smoke {
    static func run(store: StudioStore) {
        guard let dir = ProcessInfo.processInfo.environment["STUDIO_SMOKE"], !dir.isEmpty else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var log = ""
        func note(_ s: String) { log += s + "\n"; try? log.write(to: out.appendingPathComponent("smoke.txt"), atomically: true, encoding: .utf8) }
        if ProcessInfo.processInfo.environment["STUDIO_IMPORT_ENV"] == "1" { AppSettings.importDotEnv(); store.agent.load(); Task { await store.loadModels() } }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            note("repo=\(store.repo?.root.path ?? "none") files=\(store.files.count) lectures=\(store.lectures.count) sources=\(store.repoSources) profileExists=\(String(describing: store.profileExists)) stage=\(store.stage)")
            let courses = Set(store.files.map(\.course)).filter { $0 != "(root)" }.sorted()
            note("courses=\(courses)")
            if let u = ProcessInfo.processInfo.environment["STUDIO_SMOKE_URL"].flatMap(URL.init(string:)), let fs = store.repo {
                do {
                    let paths = try await WebSources.store(fs: fs, course: "", unit: "", kind: .referenceCourse, url: u, name: "ref-test", withDocuments: ProcessInfo.processInfo.environment["STUDIO_SMOKE_URL_DOCS"] == "1") { p in Task { @MainActor in note("crawl: \(p)") } }
                    let path = paths[0]
                    note("url source files: \(paths.count)")
                    let text = try fs.readString(path)
                    let heads = text.split(separator: "\n").filter { $0.hasPrefix("## ") }.prefix(12)
                    note("url source: \(path) bytes=\(text.utf8.count) headings=\(heads)")
                } catch { note("url source failed: \(error.localizedDescription)") }
            }
            if let src = ProcessInfo.processInfo.environment["STUDIO_SMOKE_IMPORT"], let fs = store.repo {
                do {
                    let r = try Scaffold(fs: fs).importCourse(from: URL(fileURLWithPath: src), folder: "imported-course", title: "Imported", code: "IMP101", kind: .course, move: false)
                    await store.refreshFiles()
                    note("import: course=\(r.course) files=\(store.files.filter { $0.course == r.course }.map(\.path)) meta=\(String(describing: store.lectures[r.course]))")
                } catch { note("import failed: \(error.localizedDescription)") }
            }
            guard let course = ProcessInfo.processInfo.environment["STUDIO_SMOKE_COURSE"] ?? courses.first else { return }
            store.selectCourse(course)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            note("stage=\(store.stage) course=\(course) word=\(store.word) talk=\(store.talk) sourceCount=\(store.sourceCount) scope=\(store.lectureScope.label)")
            await Snapshot.capture(to: out.appendingPathComponent("weeks"))
            let units = Set(store.files.filter { $0.course == course }.map(\.unit)).sorted(by: Labels.sortUnits)
            guard let deck = store.files.first(where: { $0.course == course && $0.kind == .deck }) else { note("no deck in \(course); units=\(units)"); return }
            store.openUnit(deck.unit, path: deck.path)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let probe = try? await store.preview.webView.evaluateJavaScript("JSON.stringify([document.readyState, typeof window.studioPreview, document.scripts.length, document.body ? document.body.innerHTML.length : -1, location.href])")
            note("preview probe: \(probe ?? "nil") url=\(store.preview.webView.url?.absoluteString ?? "-") loading=\(store.preview.webView.isLoading)")
            note("stage=\(store.stage) file=\(store.filePath) kind=\(store.kind) text=\(store.diskText.count) chars slides=\(store.slideCount) starts=\(store.starts.prefix(8)) notes(slide1)=\(store.notes.count) previewError=\(store.previewError ?? "none")")
            let probe2 = try? await store.preview.webView.evaluateJavaScript("""
            (() => { const svg = document.querySelector('svg[data-marpit-svg]'); const sec = svg && svg.querySelector('section'); const r = svg && svg.getBoundingClientRect(); return JSON.stringify({ svgs: document.querySelectorAll('svg[data-marpit-svg]').length, svgRect: r && [r.width, r.height], sectionW: sec && getComputedStyle(sec).width, sectionFont: sec && getComputedStyle(sec).fontSize, themeLen: (document.getElementById('theme') || {textContent: ''}).textContent.length, inner: [innerWidth, innerHeight], bodyClass: document.body.className, firstTag: document.getElementById('deck').firstElementChild && document.getElementById('deck').firstElementChild.tagName }); })()
            """)
            note("preview probe2: \(probe2 ?? "nil")")
            let probe3 = try? await store.preview.webView.evaluateJavaScript("""
            (() => { const css = (document.getElementById('theme') || {textContent: ''}).textContent; const secs = [...document.querySelectorAll('svg[data-marpit-svg] section')]; const first = secs[0]; return JSON.stringify({ cssHas20: css.includes('font-size: 20px'), cssHead: css.slice(0, 80), sections: secs.length, firstText: first && first.innerText.slice(0, 80), firstFont: first && getComputedStyle(first).fontSize, h1: first && first.querySelector('h1') && getComputedStyle(first.querySelector('h1')).fontSize, bodyBg: getComputedStyle(document.body).backgroundColor, headStyles: document.head.querySelectorAll('style').length, scheme: matchMedia('(prefers-color-scheme: dark)').matches }); })()
            """)
            note("preview probe3: \(probe3 ?? "nil")")
            let eprobe = try? await store.editor.webView.evaluateJavaScript("""
            (() => { const ed = document.querySelector('.cm-editor'); const sc = document.querySelector('.cm-scroller'); const r = ed && ed.getBoundingClientRect(); return JSON.stringify({ editorRect: r && [r.width, r.height], scrollH: sc && sc.scrollHeight, lines: document.querySelectorAll('.cm-line').length, inner: [innerWidth, innerHeight], docLen: window.studioEditor ? window.studioEditor.getValue().length : -1 }); })()
            """)
            note("editor probe: \(eprobe ?? "nil")")
            await store.runQa()
            if let qa = store.qa { note("qa: slides=\(qa.slides.count) overflow=\(qa.overflowPages) missing=\(qa.missingImagePages)") }
            store.goToSlide(min(3, max(0, store.slideCount - 1)), from: "rail")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            note("current=\(store.current) notes=\(store.notes)")
            await Snapshot.capture(to: out.appendingPathComponent("work"))
            note("git available=\(store.gitAvailable)")
            let before = store.editorText.count
            store.editor.insertBlock("\n---\n\n# {cursor}\n\n")
            try? await Task.sleep(nanoseconds: 800_000_000)
            let ins = try? await store.editor.webView.evaluateJavaScript("JSON.stringify({len: window.studioEditor.getValue().length, head: (() => { const v = window.studioEditor; return v.getValue().slice(0, 12); })()})")
            note("insertBlock: before=\(before) after=\(store.editorText.count) dirty=\(store.dirty) js=\(ins ?? "nil")")
            store.startPresentation()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            store.presentation.next()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            note("presenting=\(store.presentation.presenting) index=\(store.presentation.index) count=\(store.presentation.count) notes=\(store.presentation.notes.count) windows=\(NSApp.windows.filter { $0.isVisible }.map { $0.title })")
            let showDir = out.appendingPathComponent("present")
            try? FileManager.default.createDirectory(at: showDir, withIntermediateDirectories: true)
            for (name, c) in [("show", store.presentation.show), ("current", store.presentation.current), ("next", store.presentation.upcoming)] {
                if let img = try? await c.webView.takeSnapshot(configuration: nil), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: showDir.appendingPathComponent("\(name).png")) }
            }
            store.presentation.stop()
            note("after stop presenting=\(store.presentation.presenting) windows=\(NSApp.windows.filter { $0.isVisible }.count)")
            if let git = store.repo.map({ GitClient(root: $0.root) }), let st = try? await git.status(fetchFirst: false) {
                note("git: branch=\(st.branch) upstream=\(st.upstream ?? "-") ahead=\(st.ahead) behind=\(st.behind) changes=\(st.changes.count) last=\(st.lastCommit?.hash ?? "-")")
            }
            let (rows, err) = await store.sourceRows(course: course, unit: deck.unit)
            note("sources: rows=\(rows.count) pending=\(rows.filter(\.pending).count) indexError=\(err ?? "none") first=\(rows.prefix(3).map { "\($0.name):\($0.doc?.status ?? "disk")" })")
            if AppSettings.hasOberik {
                let fetchProbe = try? await store.agent.webView.callAsyncJavaScript("const r = await fetch('studio-app://repo/' + path); return r.status + ' ' + (await r.blob()).size", arguments: ["path": deck.path], contentWorld: .page)
                note("agent page fetch of a repo file (the Index path): \(fetchProbe ?? "failed")")
            }
            if let attach = ProcessInfo.processInfo.environment["STUDIO_SMOKE_ATTACH"], let scope = store.weekScope {
                note("attach: sending \(attach)")
                await store.sendMessage(scope: scope, text: "Describe the attached image in one sentence. Do not call any tool and do not edit any file.", attachments: [PendingAttachment(url: URL(fileURLWithPath: attach))])
                let conv = store.conversation(scope.key)
                for _ in 0..<120 { if !conv.running { break }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
                note("attach: running=\(conv.running) userAttachments=\(conv.messages.dropLast().last?.attachments.map(\.name) ?? []) error=\(conv.messages.last?.error ?? "none")\nreply=\(conv.messages.last?.content ?? "")")
            }
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_CHAT"] == "1", let scope = store.weekScope {
                note("chat: oberik=\(AppSettings.hasOberik) models=\(store.models?.models.count ?? -1) default=\(store.models?.defaultModel ?? "-")")
                if let pong = try? await store.agent.ping() { note("chat: ping -> \(pong.prefix(80))") } else { note("chat: ping failed") }
                note("chat: sending read-only turn (model=\(store.model.isEmpty ? "default" : store.model))")
                await store.sendMessage(scope: scope, text: "Call list_sources and tell me in one sentence how many source files are attached and which are ready. Do not edit any file.")
                let conv = store.conversation(scope.key)
                for _ in 0..<120 { if !conv.running { break }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
                let last = conv.messages.last
                note("chat: running=\(conv.running) session=\(conv.sessionId ?? "-") events=\(last?.events ?? []) error=\(last?.error ?? "none")\nreply=\(last?.content ?? "")\ncitations=\(last?.citations.count ?? 0)")
                await Snapshot.capture(to: out.appendingPathComponent("chat"))
            }
            note("done")
        }
    }
}
