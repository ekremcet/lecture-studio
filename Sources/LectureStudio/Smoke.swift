import Foundation
import AppKit
import SwiftUI
import StudioCore

/// Development aid: `STUDIO_SMOKE=/dir` walks the screens against the open repo without clicking,
/// and writes what it saw. `STUDIO_SMOKE_CHAT=1` adds one read-only agent turn (`STUDIO_SMOKE_PROMPT` replaces
/// the prompt); `STUDIO_SMOKE_STREAM=1` streams a long synthetic reply and reports the CPU it cost.
@MainActor
enum Smoke {
    static func run(store: StudioStore) {
        guard let dir = ProcessInfo.processInfo.environment["STUDIO_SMOKE"], !dir.isEmpty else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var log = ""
        func note(_ s: String) { log += s + "\n"; try? log.write(to: out.appendingPathComponent("smoke.txt"), atomically: true, encoding: .utf8) }
        if ProcessInfo.processInfo.environment["STUDIO_IMPORT_ENV"] == "1" { AppSettings.importDotEnv(); store.oberikSettingsChanged() }
        Task {
            // `STUDIO_WINDOW=WxH` (points) sizes the main window, for screenshots larger than the screen.
            if let spec = ProcessInfo.processInfo.environment["STUDIO_WINDOW"], let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                let parts = spec.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { w.setFrame(NSRect(x: 0, y: 0, width: parts[0], height: parts[1]), display: true) }
            }
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
            let slide = Int(ProcessInfo.processInfo.environment["STUDIO_SMOKE_SLIDE"] ?? "") ?? 3
            store.goToSlide(min(slide, max(0, store.slideCount - 1)), from: "rail")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            note("current=\(store.current) notes=\(store.notes)")
            await Snapshot.capture(to: out.appendingPathComponent("work"))
            note("git available=\(store.gitAvailable)")
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_EDIT"] != "0" {
                let before = store.editorText.count
                store.editor.insertBlock("\n---\n\n# {cursor}\n\n")
                try? await Task.sleep(nanoseconds: 800_000_000)
                let ins = try? await store.editor.webView.evaluateJavaScript("JSON.stringify({len: window.studioEditor.getValue().length, head: (() => { const v = window.studioEditor; return v.getValue().slice(0, 12); })()})")
                note("insertBlock: before=\(before) after=\(store.editorText.count) dirty=\(store.dirty) js=\(ins ?? "nil")")
            }
            store.startPresentation()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            store.presentation.next()
            try? await Task.sleep(nanoseconds: Int(ProcessInfo.processInfo.environment["STUDIO_SMOKE_PRESENT_WAIT"] ?? "") .map { UInt64($0) * 1_000_000_000 } ?? 1_500_000_000)
            note("presenting=\(store.presentation.presenting) index=\(store.presentation.index) count=\(store.presentation.count) notes=\(store.presentation.notes.count) singleScreen=\(store.presentation.singleScreen) key=\(NSApp.keyWindow?.title ?? "-") windows=\(NSApp.windows.filter { $0.isVisible }.map { $0.title })")
            let showDir = out.appendingPathComponent("present")
            try? FileManager.default.createDirectory(at: showDir, withIntermediateDirectories: true)
            // `STUDIO_SMOKE_PRESENT=1` drives the single-screen strip from inside: the events go through
            // NSApp.sendEvent, so the presenter's monitors see them as they see real input.
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_PRESENT"] == "1", let show = NSApp.windows.first(where: { $0 is ShowWindow }) {
                let pres = store.presentation
                @MainActor func shot(_ name: String) async { let r = await Snapshot.captureWindow(show, to: showDir.appendingPathComponent(name)); if !r.isEmpty { note("\(name): \(r)") } }
                func send(_ e: NSEvent?) { if let e { NSApp.sendEvent(e) } }
                note("show window: level=\(show.level.rawValue) key=\(show.isKeyWindow) behavior=\(show.collectionBehavior.rawValue) options=\(NSApp.presentationOptions.rawValue) strip=\(pres.stripVisible)")
                await shot("screen-idle.png")
                pres.pointer(at: NSPoint(x: show.frame.midX, y: show.frame.midY))
                note("pointer mid-screen: strip=\(pres.stripVisible)")
                pres.pointer(at: NSPoint(x: show.frame.midX, y: show.frame.minY + 20))
                try? await Task.sleep(nanoseconds: 600_000_000)
                note("pointer at the bottom: strip=\(pres.stripVisible)")
                await shot("screen-strip.png")
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                note("3.5 s later: strip=\(pres.stripVisible)")
                pres.startBreak(minutes: 5)
                try? await Task.sleep(nanoseconds: 700_000_000)
                note("after Break: break=\(pres.breakUntil != nil)")
                await shot("screen-break.png")
                pres.endBreak()
                pres.togglePresenterWindow()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let presenter = NSApp.windows.first { $0.title == "Presenter" }
                note("notes shown: presenterShown=\(pres.presenterShown) visible=\(presenter?.isVisible ?? false) level=\(presenter?.level.rawValue ?? -1) key=\(NSApp.keyWindow?.title ?? "-")")
                if let presenter { let r = await Snapshot.captureWindow(presenter, to: showDir.appendingPathComponent("presenter-over-slide.png")); if !r.isEmpty { note("presenter shot: \(r)") } }
                presenter?.performClose(nil)
                try? await Task.sleep(nanoseconds: 500_000_000)
                note("after closing notes: presenting=\(pres.presenting) presenterShown=\(pres.presenterShown) visible=\(presenter?.isVisible ?? false) key=\(NSApp.keyWindow?.title ?? "-")")
                send(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: show.windowNumber, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
                try? await Task.sleep(nanoseconds: 300_000_000)
                note("after right arrow: index=\(pres.index)")
            }
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
                // A long-form `STUDIO_SMOKE_PROMPT` streams for a while, which is how to check the transcript under
                // load with a real turn (`sample` the process mid-stream).
                let custom = ProcessInfo.processInfo.environment["STUDIO_SMOKE_PROMPT"].flatMap { $0.isEmpty ? nil : $0 }
                let prompt = custom ?? "Call list_sources and tell me in one sentence how many source files are attached and which are ready. Do not edit any file."
                let conv = store.conversation(scope.key)
                // `STUDIO_SMOKE_QUEUE` is sent while the turn runs (so it queues and follows on its own);
                // `STUDIO_SMOKE_STEER` goes into the turn a few seconds in.
                let queue = ProcessInfo.processInfo.environment["STUDIO_SMOKE_QUEUE"].flatMap { $0.isEmpty ? nil : $0 }
                let steer = ProcessInfo.processInfo.environment["STUDIO_SMOKE_STEER"].flatMap { $0.isEmpty ? nil : $0 }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let queue { await store.sendMessage(scope: scope, text: queue); note("queue: queued=\(conv.queued.count) running=\(conv.running)") }
                    if let steer {
                        let after = Double(ProcessInfo.processInfo.environment["STUDIO_SMOKE_STEER_AFTER"] ?? "") ?? 3
                        try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
                        Task {  // the working panel, the pending steer and the queued bubble, while the turn runs
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await Snapshot.capture(to: out.appendingPathComponent("mid"))
                        }
                        let ok = await store.steer(scope: scope, text: steer)
                        note("steer: accepted=\(ok) steeringMessages=\(conv.messages.filter(\.steering).count) running=\(conv.running)")
                    }
                }
                await store.sendMessage(scope: scope, text: prompt)
                for _ in 0..<(custom == nil ? 120 : 600) { if !conv.running { break }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
                if queue != nil {
                    // The queued message starts the next turn by itself; wait for that one too.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    for _ in 0..<600 { if !conv.running { break }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
                    note("queue: after=\(conv.messages.count) messages, queued=\(conv.queued.count), lastUser=\(conv.messages.last(where: { $0.role == .user })?.content.prefix(60) ?? "")")
                }
                let last = conv.messages.last
                note("chat: running=\(conv.running) session=\(conv.sessionId ?? "-") events=\(last?.events ?? []) error=\(last?.error ?? "none")\nreply=\(last?.content ?? "")\ncitations=\(last?.citations.count ?? 0)")
                await Snapshot.capture(to: out.appendingPathComponent("chat"))
            }
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_WATCH"] == "1", let fs = store.repo {
                // Another process adds a file to the library: the watcher must bring it into the list without a relaunch.
                // Only against a scratch copy of a library: this writes into the repo folder.
                let before = store.files.count
                let sh = Process()
                sh.executableURL = URL(fileURLWithPath: "/bin/sh")
                let rel = "\(store.course)/watch-test/watch-test-slides.md"
                sh.arguments = ["-c", "mkdir -p '\(fs.root.path)/\(store.course)/watch-test' && printf -- '---\nmarp: true\n---\n# Watched\n' > '\(fs.root.path)/\(rel)'"]
                try? sh.run(); sh.waitUntilExit()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                note("watch: before=\(before) after=\(store.files.count) listed=\(store.files.contains { $0.path == rel })")
            }
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_STREAM"] == "1", let scope = store.weekScope {
                // A long markdown reply, streamed the way the bridge delivers it (the whole text so far, about
                // twelve posts a second). The transcript re-rendered and re-laid-out everything per post before
                // 2026-09-09 and froze; this reports the CPU the process spent while the reply streamed.
                let conv = store.conversation(scope.key)
                let reply = (1...40).map { i in
                    "## Section \(i)\nSome **bold** text for section \(i) with a [link](https://example.com) and `code`.\n"
                    + (1...8).map { "- item \($0) of section \(i) with a bit more text so the line wraps inside the bubble" }.joined(separator: "\n")
                    + "\n\n1. first\n2. second\n"
                }.joined(separator: "\n")
                // The freeze had long finished replies above the streaming one: those rows must stay cheap.
                for i in 1...8 {
                    conv.messages.append(ChatMessage(role: .user, content: "earlier question \(i)"))
                    conv.messages.append(ChatMessage(role: .assistant, content: reply))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // the transcript settles, as before a real send
                conv.messages.append(ChatMessage(role: .user, content: "stream test"))
                conv.messages.append(ChatMessage(role: .assistant, content: ""))
                conv.running = true
                let cpu0 = Smoke.cpuSeconds(), t0 = Date()
                let steps = 300
                var mainThreadStalls = 0
                for s in 1...steps {
                    let n = reply.count * s / steps
                    conv.patchLast { $0.content = String(reply.prefix(n)) }
                    let before = Date()
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    if Date().timeIntervalSince(before) > 0.25 { mainThreadStalls += 1 }
                }
                conv.patchLast(now: true) { $0.content = reply }
                conv.running = false
                try? await Task.sleep(nanoseconds: 700_000_000)
                note("stream: chars=\(reply.count) steps=\(steps) wall=\(String(format: "%.1f", Date().timeIntervalSince(t0)))s cpu=\(String(format: "%.2f", Smoke.cpuSeconds() - cpu0))s stalls=\(mainThreadStalls)")
                await Snapshot.capture(to: out.appendingPathComponent("stream"))
                // The archive round trip: the conversation is on disk, listed for this scope only, and comes back whole.
                store.saveConversation(conv)
                let history = store.chatHistory(scope.key)
                let back = store.archive?.load(scope: scope.key, id: conv.id)
                note("history: scope=\(scope.key) count=\(history.count) first=\(history.first?.title ?? "-") restored=\(back?.messages == conv.messages) courseScope=\(store.chatHistory(store.lectureScope.key).count)")
                // A second, older conversation so the list has two rows; then the list itself in a window for the snapshot.
                store.resetConversation(scope.key)
                conv.messages.append(ChatMessage(role: .user, content: "Draft the speaker notes for slides 4 to 9, two sentences each"))
                conv.messages.append(ChatMessage(role: .assistant, content: "Done: nine notes added."))
                store.saveConversation(conv)
                let list = ChatHistoryList(scope: scope, current: conv.id, onOpen: {}).environment(store)
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
                w.title = "History"
                w.contentView = NSHostingView(rootView: list)
                w.center(); w.orderFront(nil)
                try? await Task.sleep(nanoseconds: 800_000_000)
                let shot = Process()
                shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                shot.arguments = ["-x", "-o", "-l", String(w.windowNumber), out.appendingPathComponent("history-list.png").path]
                try? shot.run(); shot.waitUntilExit()
                await Snapshot.capture(to: out.appendingPathComponent("history"))
                w.orderOut(nil)
                // Back to the long one from the list: it opens at its end.
                if let older = store.chatHistory(scope.key).first(where: { $0.id != conv.id }) { store.openChat(scope.key, id: older.id) }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                note("history: reopened=\(conv.messages.count) messages, title=\(conv.title)")
                await Snapshot.capture(to: out.appendingPathComponent("history-open"))
            }
            if ProcessInfo.processInfo.environment["STUDIO_SMOKE_HOME"] == "1" { store.backToLectures(); try? await Task.sleep(nanoseconds: 3_000_000_000) }
            note("done")
        }
    }

    /// CPU time this process has used, user and system.
    static func cpuSeconds() -> Double {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
    }
}
