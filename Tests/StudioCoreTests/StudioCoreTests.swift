import XCTest
@testable import StudioCore

final class StudioCoreTests: XCTestCase {
    var tmp: URL!
    var fs: RepoFS!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("studio-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        fs = RepoFS(root: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testParseUnit() {
        XCTAssertEqual(parseUnit("week3"), ParsedUnit(prefix: "week", n: 3, sep: ""))
        XCTAssertEqual(parseUnit("calistay-3"), ParsedUnit(prefix: "calistay", n: 3, sep: "-"))
        XCTAssertEqual(parseUnit("Session12"), ParsedUnit(prefix: "session", n: 12, sep: ""))
        XCTAssertNil(parseUnit("lab-sessions"))
    }

    func testLabels() {
        XCTAssertEqual(Labels.courseLabel("cs231-data-structures"), "CS231 Data Structures")
        XCTAssertEqual(Labels.courseLabel("ai-in-science"), "Ai In Science")
        XCTAssertEqual(Labels.courseLabel("x", LectureMeta(title: "Talk", code: "")), "Talk")
        XCTAssertEqual(Labels.unitLabel("week3"), "Week 3")
        XCTAssertEqual(Labels.unitLabel("calistay-2"), "Workshop 2")
        XCTAssertEqual(Labels.unitLabel(""), "Course files")
        XCTAssertEqual(Labels.unitWord(nil, units: ["week1", "week2", "session1"]), "week")
        XCTAssertEqual(Labels.unitWord(LectureMeta(unitPrefix: "day")), "day")
        XCTAssertTrue(Labels.sortUnits("week2", "week10"))
        XCTAssertTrue(Labels.sortUnits("", "week1"))
    }

    func testNotesSkipDirectives() {
        let md = "---\nmarp: true\n---\n\n# A\n<!-- _class: lead -->\n<!-- Say: welcome everyone -->\n\n---\n\n# B\n<!-- footer: x -->\n<!-- second slide note -->\n"
        let starts = [0, 8]
        XCTAssertEqual(Slides.notes(md, starts: starts, index: 0), ["Say: welcome everyone"])
        XCTAssertEqual(Slides.notes(md, starts: starts, index: 1), ["second slide note"])
        XCTAssertEqual(Slides.slideForLine(starts, 9), 1)
        XCTAssertEqual(Slides.slideForLine(starts, 3), 0)
    }

    func testRepoFSGuards() throws {
        XCTAssertThrowsError(try fs.resolve("../outside"))
        XCTAssertThrowsError(try fs.resolve(".git/config"))
        try fs.createText("a/b.txt", "one\ntwo\nthree")
        XCTAssertThrowsError(try fs.createText("a/b.txt", "again"))
        let r = try fs.readText("a/b.txt", from: 2, to: 3)
        XCTAssertEqual(r.text, "two\nthree")
        XCTAssertEqual(r.lines, 3)
        try fs.appendText("a/b.txt", "\nfour")
        XCTAssertEqual(try fs.replaceOnce("a/b.txt", old: "three", new: "3"), 3)
        XCTAssertThrowsError(try fs.replaceOnce("a/b.txt", old: "zzz", new: "")) { e in XCTAssertEqual((e as? RepoPathError)?.message, "old text not found") }
        try fs.overwriteText("a/c.txt", "x x")
        XCTAssertThrowsError(try fs.replaceOnce("a/c.txt", old: "x", new: "y")) { e in XCTAssertEqual((e as? RepoPathError)?.message, "old text matches more than once; include more context") }
        XCTAssertEqual(try fs.listDir("a").map(\.name), ["b.txt", "c.txt"])
    }

    func testTalkTemplateWithEmptyProfile() {
        let t = Templates.talk(.init(title: "AI in Science", event: nil, date: "01.01.2026", profile: .empty()))
        XCTAssertTrue(t.contains("# AI in Science"))
        XCTAssertTrue(t.contains("**01.01.2026**"))
        XCTAssertFalse(t.contains("## Contact"))
        XCTAssertTrue(t.hasSuffix("# Thank You\n\n"))
    }

    func testDeckTemplateFromProfile() {
        let p = Profile(name: "Ada Lovelace", email: "ada@example.edu", contact: ["Office hours: Tue 14-16"])
        let d = Templates.deck(.init(code: "CS101", courseName: "Intro", week: 2, topic: "Stacks", date: "02.02.2026", previousTopic: "Arrays", profile: p, unitLabel: "session"))
        XCTAssertTrue(d.contains("header: \"CS101 - Intro\""))
        XCTAssertTrue(d.contains("footer: \"Session 2: Stacks\""))
        XCTAssertTrue(d.contains("# Recap: Session 1"))
        XCTAssertTrue(d.contains("- Arrays"))
        XCTAssertTrue(d.contains("**Instructor:** Ada Lovelace"))
        XCTAssertTrue(d.contains("- **Office hours:** Tue 14-16"))
    }

    func testScaffoldCourseAndWeek() throws {
        try ProfileStore(fs: fs).write(Profile(name: "Ada", language: "English", unitLabel: "session"))
        let s = Scaffold(fs: fs)
        let c = try s.lecture(code: "CS101", name: "Intro to CS", language: nil, semester: "Fall 2026", unitPrefix: nil, withSyllabus: true, withContext: true)
        XCTAssertEqual(c.course, "cs101-intro-to-cs")
        XCTAssertEqual(LectureMetaStore(fs: fs).read(c.course).unitPrefix, "session")
        let w = try s.week(course: c.course, week: 1, topic: "Hello", withGuide: true)
        XCTAssertEqual(w.unit, "session1")
        XCTAssertEqual(w.created.count, 2)
        XCTAssertThrowsError(try s.week(course: c.course, week: 1, topic: "Again", withGuide: false))
        let meta = courseMeta(fs: fs, course: c.course)
        XCTAssertEqual(meta.weeks, [1])
        XCTAssertEqual(meta.topics[1], "Hello")
        let idx = FilesIndex.scan(fs: fs)
        XCTAssertEqual(idx.files.first { $0.path == w.deck }?.kind, .deck)
        XCTAssertEqual(idx.files.first { $0.path == w.deck }?.title, "Session 1: Hello")
        XCTAssertEqual(idx.lectures[c.course]?.title, "Intro to CS")
    }

    func testHyphenUnits() throws {
        try fs.createText("ws/calistay-1/calistay-1-slides.md", "---\nmarp: true\nheader: \"WS - Workshop\"\n---\n# A")
        try fs.createText("ws/calistay-2/calistay-2-slides.md", "---\nmarp: true\n---\n# B")
        let meta = courseMeta(fs: fs, course: "ws")
        XCTAssertEqual(meta.unitPrefix, "calistay")
        XCTAssertEqual(meta.unitSep, "-")
        XCTAssertEqual(meta.weeks, [1, 2])
        XCTAssertEqual(meta.courseName, "Workshop")
        XCTAssertEqual(meta.code, "WS")
    }

    func testImportCourseAndCustomFolder() throws {
        let src = tmp.appendingPathComponent("outside-course")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("week1"), withIntermediateDirectories: true)
        try "---\nmarp: true\n---\n# A".write(to: src.appendingPathComponent("week1/week1-slides.md"), atomically: true, encoding: .utf8)
        let lib = tmp.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        let s = Scaffold(fs: RepoFS(root: lib))
        let r = try s.importCourse(from: src, folder: "cs101", title: "Intro", code: "cs101", kind: .course, move: false)
        XCTAssertEqual(r.course, "cs101")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("cs101/week1/week1-slides.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "copy keeps the source")
        let meta = LectureMetaStore(fs: RepoFS(root: lib)).read("cs101")
        XCTAssertEqual(meta.code, "CS101")
        XCTAssertEqual(meta.unitPrefix, "week")
        XCTAssertThrowsError(try s.importCourse(from: src, folder: "cs101", title: "x", code: nil, kind: .course, move: false))
        let deck = tmp.appendingPathComponent("talk.md")
        try "---\nmarp: true\n---\n# T".write(to: deck, atomically: true, encoding: .utf8)
        let t = try s.importCourse(from: deck, folder: "my-talk", title: "My Talk", code: nil, kind: .talk, move: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("my-talk/my-talk.md").path))
        XCTAssertEqual(LectureMetaStore(fs: RepoFS(root: lib)).read(t.course).kind, .talk)
        let c = try s.lecture(code: "", name: "Something Long", language: nil, semester: nil, unitPrefix: nil, withSyllabus: false, withContext: false, folder: "short")
        XCTAssertEqual(c.course, "short")
        XCTAssertThrowsError(try s.lecture(code: "", name: "X", language: nil, semester: nil, unitPrefix: nil, withSyllabus: false, withContext: false, folder: "Bad Name"))
    }

    func testSlug() {
        XCTAssertEqual(slug("Yazılım Mühendisliği Çalıştayı"), "yazilim-muhendisligi-calistayi")
        XCTAssertEqual(slug("  AI in Science! "), "ai-in-science")
    }

    func testSourcesAndDotEnv() throws {
        try fs.createText("sources/a.pdf", "x")
        try fs.createText("c1/sources/b.md", "y")
        try fs.createText("c1/week1/sources/c.txt", "z")
        XCTAssertEqual(SourceFolders.sources(fs: fs, course: "c1", unit: "week1").map(\.scope), [.global, .lecture, .unit])
        XCTAssertEqual(SourceFolders.sources(fs: fs, course: "", unit: "").count, 1)
        XCTAssertThrowsError(try SourceFolders.remove(fs: fs, path: "c1/week1/x.md"))
        XCTAssertEqual(FilesIndex.scan(fs: fs).sources, 3)
        XCTAssertEqual(DotEnv.parse("A=1\n# c\nB=\"two\"\n"), ["A": "1", "B": "two"])
    }
}

final class WebSourcesTests: XCTestCase {
    func testHtmlToMarkdown() {
        let html = """
        <html><head><title>Week 3 &amp; 4</title><style>p{}</style></head><body><nav>menu</nav>
        <h1>Schedule</h1><p>Read <a href="readings/ch2.pdf">chapter 2</a> before <strong>Tuesday</strong>.</p>
        <ul><li>Lecture: <em>Search</em></li><li>Lab</li></ul><script>x()</script></body></html>
        """
        let (title, md) = WebSources.htmlToMarkdown(html, base: URL(string: "https://example.edu/course/spring/index.html")!)
        XCTAssertEqual(title, "Week 3 & 4")
        XCTAssertTrue(md.hasPrefix("# Schedule"))
        XCTAssertTrue(md.contains("[chapter 2](https://example.edu/course/spring/readings/ch2.pdf)"))
        XCTAssertTrue(md.contains("**Tuesday**"))
        XCTAssertTrue(md.contains("- Lecture: *Search*"))
        XCTAssertFalse(md.contains("menu"))
        XCTAssertFalse(md.contains("x()"))
    }

    func testScopeAndLinks() {
        XCTAssertEqual(WebSources.scope(of: URL(string: "https://mit-mi.github.io/mmai-course/spring2026/schedule/")!), "mit-mi.github.io/mmai-course/spring2026/")
        XCTAssertEqual(WebSources.scope(of: URL(string: "https://x.org/a/b/page.html")!), "x.org/a/b/")
        let links = WebSources.links(in: "<a href='../week1/'>w</a><a href=\"#top\">t</a><a href=\"https://other.org/\">o</a>", base: URL(string: "https://x.org/a/b/")!)
        XCTAssertEqual(links.map(\.absoluteString), ["https://x.org/a/week1/", "https://other.org/"])
    }
}

final class TermsTests: XCTestCase {
    func testRedateAndDiff() {
        let start = Terms.isoDate("2026-09-28")!
        let deck = "# T\n\n**Date:** 30.09.2025\n\n---\n\n# Next Class\n\n- **Date:** DD.MM.YYYY\n- **Topic:** x\n"
        let out = Terms.redate(deck, unit: 3, start: start)
        XCTAssertTrue(out.contains("**Date:** 12.10.2026"))
        XCTAssertTrue(out.contains("- **Date:** 19.10.2026"))
        let d = Compare.lines("a\nb\nc", "a\nc\nd")
        XCTAssertEqual(d.map(\.kind), [.same, .removed, .same, .added])
    }

    func testNewTermCopiesRedatesArchives() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("terms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fs = RepoFS(root: tmp)
        try fs.createText("c-fall25/week1/week1-slides.md", "# W1\n\n**Date:** 29.09.2025\n")
        try fs.createText("c-fall25/week2/week2-slides.md", "# W2\n\n**Date:** 06.10.2025\n")
        try fs.createText("c-fall25/syllabus.md", "# S")
        try fs.createText("c-fall25/export.pdf", "x")
        try LectureMetaStore(fs: fs).write("c-fall25", LectureMeta(title: "Course", code: "C1", term: "Fall 2025", kind: .course, unitPrefix: "week"))
        let r = try await Terms.newTerm(fs: fs, from: "c-fall25", folder: "c-fall26", term: "Fall 2026", startDate: Terms.isoDate("2026-09-28"), copyUnits: true, archiveOld: true)
        XCTAssertEqual(r.units, ["week1", "week2"])
        XCTAssertEqual(r.redated, 2)
        XCTAssertTrue(try fs.readString("c-fall26/week2/week2-slides.md").contains("05.10.2026"))
        XCTAssertFalse(fs.exists("c-fall26/export.pdf"))
        let m = LectureMetaStore(fs: fs).read("c-fall26")
        XCTAssertEqual(m.term, "Fall 2026"); XCTAssertEqual(m.derivedFrom, "c-fall25"); XCTAssertEqual(m.code, "C1"); XCTAssertEqual(m.startDate, "2026-09-28")
        XCTAssertEqual(LectureMetaStore(fs: fs).read("c-fall25").archived, true)
        try fs.appendText("c-fall26/week1/week1-slides.md", "\nnew line\n")
        try fs.createText("c-fall26/week3/week3-slides.md", "# W3")
        let cmp = Compare.units(fs: fs, left: "c-fall25", right: "c-fall26")
        XCTAssertEqual(cmp.map(\.change), [.changed, .changed, .onlyRight])
        XCTAssertEqual(cmp[0].added, 3) // the moved date plus the two appended lines
    }
}

final class FolderChoiceTests: XCTestCase {
    func testCourseInExistingAndLinkedFolders() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("folders-\(UUID().uuidString)")
        let lib = tmp.appendingPathComponent("lib"), elsewhere = tmp.appendingPathComponent("elsewhere/my-course")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fs = RepoFS(root: lib)
        let s = Scaffold(fs: fs)
        // An existing empty folder inside the library is used as it is.
        try fs.mkdir("pre-made")
        let a = try s.lecture(code: "", name: "Pre Made", language: nil, semester: nil, unitPrefix: nil, withSyllabus: true, withContext: false, folder: "pre-made")
        XCTAssertEqual(a.course, "pre-made")
        XCTAssertThrowsError(try s.lecture(code: "", name: "Again", language: nil, semester: nil, unitPrefix: nil, withSyllabus: false, withContext: false, folder: "pre-made"))
        // A folder elsewhere is linked into the library.
        let b = try s.talk(name: "My Course", event: nil, date: nil, language: nil, folder: "my-course", location: elsewhere)
        XCTAssertEqual(b.course, "my-course")
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("my-course.md").path))
        let attrs = try FileManager.default.attributesOfItem(atPath: lib.appendingPathComponent("my-course").path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(FilesIndex.scan(fs: fs).files.filter { $0.course == "my-course" }.count, 1)
    }
}

final class TermValueTests: XCTestCase {
    func testParseAndOrder() {
        XCTAssertEqual(TermValue.parse("Fall 2026"), TermValue(season: "Fall", year: 2026))
        XCTAssertEqual(TermValue.parse("fall26"), TermValue(season: "Fall", year: 2026))
        XCTAssertEqual(TermValue.parse("Güz 2025"), TermValue(season: "Fall", year: 2025))
        XCTAssertEqual(TermValue.parse("2026 Spring"), TermValue(season: "Spring", year: 2026))
        XCTAssertNil(TermValue.parse("Research Seminar"))
        XCTAssertTrue(TermValue.parse("Spring 2026")!.order < TermValue.parse("Fall 2026")!.order)
        XCTAssertEqual(TermValue.parse("Fall 2025")!.next.text, "Fall 2026")
    }
}

/// The chat transcript's hot path: markdown parsed once per text, stream patches landing in batches.
final class ChatStreamTests: XCTestCase {
    // MARK: chat markdown and stream batching

    func testChatMarkdownBlocks() {
        let text = """
        ## Plan
        First **bold** line
        second line of the paragraph

        - one
        - two
          continues two
        1. first
        2) second
        ```
        code a
          code b
        ```
        """
        let b = ChatMarkdown.blocks(text)
        XCTAssertEqual(b.count, 5)
        guard b.count == 5 else { return }
        XCTAssertEqual(b[0], .heading(2, ChatMarkdown.inline("Plan")))
        XCTAssertEqual(b[1], .paragraph(ChatMarkdown.inline("First **bold** line second line of the paragraph")))
        XCTAssertEqual(b[2], .bullet([ChatMarkdown.inline("one"), ChatMarkdown.inline("two continues two")]))
        XCTAssertEqual(b[3], .numbered([ChatMarkdown.inline("first"), ChatMarkdown.inline("second")]))
        XCTAssertEqual(b[4], .code("code a\n  code b"))
        // Inline markdown resolved: the bold run is one attributed run, the plain text keeps its words.
        if case .paragraph(let a) = b[1] { XCTAssertEqual(String(a.characters), "First bold line second line of the paragraph") } else { XCTFail() }
        XCTAssertEqual(ChatMarkdown.blocks(""), [])
        XCTAssertEqual(ChatMarkdown.blocks("```\nopen fence"), [.code("open fence")])
    }

    func testChatMarkdownCache() {
        let text = "- a\n- b\n\nend"
        let first = ChatMarkdown.cached(text)
        XCTAssertEqual(first, ChatMarkdown.blocks(text))
        XCTAssertEqual(ChatMarkdown.cached(text), first)
        XCTAssertNotEqual(ChatMarkdown.cached(text + "!"), first)
    }

    func testPendingPatchesDrainInOrderOnce() {
        var q = PendingPatches<[String]>()
        var value = ["start"]
        XCTAssertFalse(q.drain(into: &value))
        q.add { $0.append("a") }
        q.add { $0.append("b") }
        q.add { $0 = ["replaced"] }
        q.add { $0.append("c") }
        XCTAssertEqual(q.count, 4)
        XCTAssertTrue(q.drain(into: &value))
        XCTAssertEqual(value, ["replaced", "c"])
        XCTAssertTrue(q.isEmpty)
        XCTAssertFalse(q.drain(into: &value))
        XCTAssertEqual(value, ["replaced", "c"])
        q.add { $0.append("d") }
        q.clear()
        XCTAssertFalse(q.drain(into: &value))
    }
}

/// The library folder is watched for changes made by other processes.
final class FolderWatcherTests: XCTestCase {
    func testReportsWritesFromAnotherProcessRelativeToTheRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("week1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exp = expectation(description: "external change reported")
        exp.assertForOverFulfill = false
        var got: [String] = []
        let w = FolderWatcher(root: dir, latency: 0.1, quiet: 0.3) { paths in got = paths; exp.fulfill() }
        w.start()
        defer { w.stop() }
        Thread.sleep(forTimeInterval: 0.3)
        // Another process writes (the watcher ignores this process's own writes, as the app's are handled elsewhere).
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "echo '# hi' > '\(dir.path)/week1/deck.md'; echo x > '\(dir.path)/.git/index'"]
        try sh.run(); sh.waitUntilExit()
        wait(for: [exp], timeout: 8)
        XCTAssertTrue(got.contains { $0 == "week1/deck.md" || $0 == "week1" }, "\(got)")
        XCTAssertFalse(got.contains { $0.hasPrefix(".git") }, "\(got)")
    }
}

/// Conversations on disk: one file each, per library and per scope, newest first.
final class ChatArchiveTests: XCTestCase {
    func testSaveListLoadDeletePerScope() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("chat-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = URL(fileURLWithPath: "/tmp/lectures")
        let archive = ChatArchive.forRepo(repo, base: base)
        XCTAssertTrue(archive.root.lastPathComponent.hasPrefix("lectures-"))
        XCTAssertEqual(ChatArchive.forRepo(repo, base: base).root, archive.root)
        XCTAssertNotEqual(ChatArchive.forRepo(URL(fileURLWithPath: "/tmp/other/lectures"), base: base).root, archive.root)

        var m1 = ChatMessage(role: .user, content: "Plan week 3\nwith three readings")
        m1.attachments = [ChatAttachment(kind: "file", url: "data:text/plain;base64,aGk=", name: "notes.txt", mime_type: "text/plain")]
        var m2 = ChatMessage(role: .assistant, content: "Here is the **plan**.")
        m2.events = ["▶ list_sources {}", "✓ list_sources"]
        m2.citations = [ChatCitation(marker: 1, title: "Reading A", page: 4)]
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let older = ArchivedChat(id: UUID(), scope: "cs101/week3", sessionId: "s-1", title: ArchivedChat.title(for: [m1, m2]), created: t0, updated: t0, messages: [m1, m2])
        // Saved within the same second as `older`: the fraction still orders them.
        let newer = ArchivedChat(id: UUID(), scope: "cs101/week3", sessionId: nil, title: "second", created: t0 + 0.25, updated: t0 + 0.5, messages: [ChatMessage(role: .user, content: "second")])
        let course = ArchivedChat(id: UUID(), scope: "cs101", sessionId: "s-2", title: "course", created: t0, updated: t0, messages: [ChatMessage(role: .user, content: "course-level")])
        try archive.save(older); try archive.save(newer); try archive.save(course)

        XCTAssertEqual(older.title, "Plan week 3")
        let week = archive.list(scope: "cs101/week3")
        XCTAssertEqual(week.map(\.id), [newer.id, older.id])
        XCTAssertEqual(week.map(\.messageCount), [1, 2])
        XCTAssertEqual(archive.list(scope: "cs101").map(\.id), [course.id])
        XCTAssertEqual(archive.list(scope: "cs101/week4"), [])
        XCTAssertEqual(archive.latest(scope: "cs101/week3")?.id, newer.id)

        let back = try XCTUnwrap(archive.load(scope: "cs101/week3", id: older.id))
        XCTAssertEqual(back, older)
        XCTAssertEqual(back.messages[1].citations.first?.label, "Reading A")
        XCTAssertEqual(back.messages[0].attachments.first?.name, "notes.txt")

        try archive.delete(scope: "cs101/week3", id: newer.id)
        XCTAssertEqual(archive.list(scope: "cs101/week3").map(\.id), [older.id])
        XCTAssertNil(archive.load(scope: "cs101/week3", id: newer.id))
        try archive.delete(scope: "cs101/week3", id: newer.id)  // gone already: no error
        XCTAssertEqual(archive.folder(scope: "").lastPathComponent, "_")
        XCTAssertEqual(archive.folder(scope: "cs101/week3").lastPathComponent, "cs101__week3")
    }

    func testMessageDecodesOlderFilesAndKeepsSteering() throws {
        // A file written before `steering` existed: no key at all, and no `events` either.
        let older = #"{"id":"6DA0A90E-FB02-40FC-BB7D-6F6F7C41C153","role":"user","content":"hi"}"#
        let m = try JSONDecoder().decode(ChatMessage.self, from: Data(older.utf8))
        XCTAssertEqual(m.content, "hi")
        XCTAssertFalse(m.steering)
        XCTAssertEqual(m.events, [])
        var st = ChatMessage(role: .user, content: "stop after week 3")
        st.steering = true
        let back = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back, st)
        XCTAssertTrue(back.steering)
    }

    func testTitleOfEmptyOrLong() {
        XCTAssertEqual(ArchivedChat.title(for: []), "")
        XCTAssertEqual(ArchivedChat.title(for: [ChatMessage(role: .assistant, content: "hi")]), "")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(ArchivedChat.title(for: [ChatMessage(role: .user, content: long)]).count, 72)
    }
}

/// The rhythm itself: the text the lecturer types, what it means, and how it is spoken back to them.
final class LecturePlanTests: XCTestCase {
    func testParseAcceptsWhateverTheLecturerTypes() {
        XCTAssertEqual(LecturePlan("20 5 20 15").lengths, [20, 5, 20, 15])
        XCTAssertEqual(LecturePlan("20, 5, 20, 15").lengths, [20, 5, 20, 15])
        XCTAssertEqual(LecturePlan("20/5 20/15").lengths, [20, 5, 20, 15])
        XCTAssertEqual(LecturePlan("").lengths, [20, 5, 20, 15], "nothing typed is the default rhythm")
        XCTAssertEqual(LecturePlan("   ").lengths, [20, 5, 20, 15])
        XCTAssertEqual(LecturePlan("45").lengths, [45, 10], "a lone block still needs a break")
        XCTAssertEqual(LecturePlan("20 5 20").lengths, [20, 5, 20, 5], "a trailing block gets the break before it")
        XCTAssertEqual(LecturePlan("0 999 7 3").lengths, [1, 180, 7, 3], "minutes are clamped to 1…180")
        XCTAssertEqual(LecturePlan("1 1 1 1 1 1 1 1 1 1 1 1 1 1").lengths.count, 12, "six blocks is the ceiling")
    }

    func testTextRoundTrips() {
        for f in LectureFormat.builtIn {
            XCTAssertEqual(f.plan.text, f.rhythm, f.name)
            XCTAssertFalse(f.icon.isEmpty, "\(f.name) ships with a symbol")
        }
        XCTAssertEqual(Set(LectureFormat.builtIn.map(\.rhythm)).count, LectureFormat.builtIn.count, "built-in formats are distinct")
        XCTAssertEqual(LectureFormat.builtIn.first?.rhythm, LecturePlan.defaultText, "the app's own rhythm comes first")
        XCTAssertEqual(LecturePlan.clamp(0), 1)
        XCTAssertEqual(LecturePlan.clamp(999), 180)
    }

    func testHowARhythmReads() {
        let p = LecturePlan("20 5 20 15")
        XCTAssertEqual(p.text, "20 5 20 15")
        XCTAssertEqual(p.compact, "20 / 5 · 20 / 15")
        XCTAssertEqual(p.summary, "teaching 20 min, break 5 min, teaching 20 min, break 15 min")
        XCTAssertEqual(p.roundMinutes, 60)
        XCTAssertEqual(p.blocks, 2)
    }
}

/// The lecturer's clock: a block counts down, the break after it takes over on its own (or does not), and the
/// break's end arms the next block of the rhythm.
final class LectureCountdownTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let plan = LecturePlan("20 5 20 15")

    func testWalksThePlanAndStartsOver() {
        var c = LectureCountdown(plan: plan)
        XCTAssertFalse(c.running)
        XCTAssertFalse(c.counting)
        XCTAssertNil(c.until)
        XCTAssertEqual(c.blocks, 2)
        c.start(now: t0)
        XCTAssertTrue(c.counting)
        XCTAssertEqual(c.block, 1)
        XCTAssertEqual(c.blockMinutes, 20)
        XCTAssertEqual(c.nextBreakMinutes, 5)
        XCTAssertEqual(c.until, t0.addingTimeInterval(1200))
        XCTAssertEqual(c.secondsLeft(now: t0), 1200)
        XCTAssertEqual(c.secondsLeft(now: t0.addingTimeInterval(60)), 1140)
        // Nothing happens while the block runs, and the block is over exactly once.
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1199)), .none)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1200)), .startBreak(minutes: 5))
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1201)), .none)
        // The break has the room: the clock is on but not counting, so no second break can start.
        XCTAssertTrue(c.running)
        XCTAssertFalse(c.counting)
        XCTAssertNil(c.until)
        XCTAssertNil(c.secondsLeft(now: t0.addingTimeInterval(1300)))
        XCTAssertEqual(c.block, 1)
        // Its end arms the second block, which hands over to the longer break.
        XCTAssertEqual(c.resume(now: t0.addingTimeInterval(1500)), t0.addingTimeInterval(2700))
        XCTAssertEqual(c.block, 2)
        XCTAssertEqual(c.blockMinutes, 20)
        XCTAssertEqual(c.nextBreakMinutes, 15)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(2700)), .startBreak(minutes: 15))
        // After the last break of the plan the first block starts again.
        XCTAssertEqual(c.resume(now: t0.addingTimeInterval(3600)), t0.addingTimeInterval(4800))
        XCTAssertEqual(c.index, 0)
        XCTAssertEqual(c.block, 1)
        XCTAssertEqual(c.until, t0.addingTimeInterval(4800))
    }

    func testInterruptedBlockKeepsItsSeconds() {
        var c = LectureCountdown(plan: plan)
        c.start(now: t0)
        // Ten minutes into the block the lecturer takes a break of their own.
        c.suspend(now: t0.addingTimeInterval(600))
        XCTAssertEqual(c.pausedLeft, 600)
        XCTAssertNil(c.until)
        XCTAssertEqual(c.block, 1)
        // The break's end gives the block back its ten minutes, in the same block of the plan.
        XCTAssertEqual(c.resume(now: t0.addingTimeInterval(900)), t0.addingTimeInterval(1500))
        XCTAssertEqual(c.block, 1, "a stretch mid-block does not move the lecture on")
        XCTAssertEqual(c.secondsLeft(now: t0.addingTimeInterval(900)), 600)
        // A break the clock called does not give anything back: that block is spent.
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1500)), .startBreak(minutes: 5))
        XCTAssertNil(c.pausedLeft)
        XCTAssertEqual(c.resume(now: t0.addingTimeInterval(1800)), t0.addingTimeInterval(3000))
        XCTAssertEqual(c.block, 2)
    }

    func testAutoBreakOffLeavesTheBreakToTheLecturer() {
        var c = LectureCountdown(plan: plan, autoBreak: false)
        c.start(now: t0)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1200)), .timeIsUp)
        XCTAssertFalse(c.running)
        XCTAssertFalse(c.counting)
        XCTAssertNil(c.resume(now: t0.addingTimeInterval(1500)))
        // The block is spent: starting again begins the second block of the plan, not this one again.
        XCTAssertEqual(c.block, 2)
        c.start(now: t0.addingTimeInterval(1500))
        XCTAssertEqual(c.block, 2)
        XCTAssertEqual(c.until, t0.addingTimeInterval(1500 + 1200))
    }

    func testStopKeepsThePlaceAndResetDoesNot() {
        var c = LectureCountdown(plan: plan)
        c.start(now: t0)
        c.tick(now: t0.addingTimeInterval(1200))          // into the first break
        c.resume(now: t0.addingTimeInterval(1500))        // second block, counting
        c.stop()
        XCTAssertFalse(c.running)
        XCTAssertNil(c.until)
        XCTAssertEqual(c.block, 2)
        XCTAssertNil(c.resume(now: t0.addingTimeInterval(2000)), "a clock the lecturer stopped stays stopped")
        c.start(now: t0.addingTimeInterval(2000))
        XCTAssertEqual(c.block, 2, "starting again picks the lecture up where it was")
        c.reset()
        XCTAssertFalse(c.running)
        XCTAssertEqual(c.block, 1)
        XCTAssertEqual(c.index, 0)
    }

    func testChangingTheRhythmKeepsTheBlockInProgress() {
        var c = LectureCountdown(plan: plan)
        c.start(now: t0)
        c.tick(now: t0.addingTimeInterval(1200))
        c.resume(now: t0.addingTimeInterval(1500))        // second block of the old plan, until 2700
        c.use(LecturePlan("45 15 45 20"))
        XCTAssertEqual(c.block, 2, "the place in the rhythm is kept")
        XCTAssertEqual(c.until, t0.addingTimeInterval(2700), "the block in progress keeps its end")
        XCTAssertEqual(c.nextBreakMinutes, 20)
        // A plan too short for the place wraps instead of leaving the clock off its end.
        c.use(LecturePlan("30 10"))
        XCTAssertEqual(c.block, 1)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(2700)), .startBreak(minutes: 10))
        XCTAssertEqual(c.resume(now: t0.addingTimeInterval(2800)), t0.addingTimeInterval(4600))
        XCTAssertEqual(c.index, 0, "the new plan is one round long, so it starts again")
        XCTAssertEqual(c.blockMinutes, 30)
    }
}

final class LectureFormatTests: XCTestCase {
    func testFirstRunKeepsTheOldRhythm() {
        // Nothing saved yet and the old single rhythm was a built-in one: that format is the default.
        let kept = LectureFormat.resolve(saved: nil, defaultId: nil, legacyRhythm: "45 15 45 15")
        XCTAssertEqual(kept.formats.map(\.name), LectureFormat.builtIn.map(\.name))
        XCTAssertEqual(kept.formats.first { $0.id == kept.defaultId }?.rhythm, "45 15 45 15")
        // A rhythm of the lecturer's own lands as a format of its own, and stays the default.
        let own = LectureFormat.resolve(saved: nil, defaultId: nil, legacyRhythm: "30 10 30 10 30 20")
        XCTAssertEqual(own.formats.count, LectureFormat.builtIn.count + 1)
        XCTAssertEqual(own.formats.last?.name, "My rhythm")
        XCTAssertEqual(own.formats.last?.id, own.defaultId)
        // No old setting at all: the built-in list, its first format the default.
        let fresh = LectureFormat.resolve(saved: nil, defaultId: nil, legacyRhythm: nil)
        XCTAssertEqual(fresh.defaultId, fresh.formats[0].id)
        XCTAssertEqual(fresh.formats[0].name, "Pomodoro")
    }

    func testSavedListWins() {
        let mine = [LectureFormat(name: "Lab", icon: "flask", rhythm: "60 10"), LectureFormat(name: "Talk", rhythm: "40 5")]
        let r = LectureFormat.resolve(saved: mine, defaultId: mine[1].id, legacyRhythm: "20 5 20 15")
        XCTAssertEqual(r.formats, mine, "the old rhythm is not added again once a list is saved")
        XCTAssertEqual(r.defaultId, mine[1].id)
        // A default that was removed falls back to the first format; an emptied list to the built-in one.
        XCTAssertEqual(LectureFormat.resolve(saved: mine, defaultId: UUID(), legacyRhythm: nil).defaultId, mine[0].id)
        XCTAssertEqual(LectureFormat.resolve(saved: [], defaultId: nil, legacyRhythm: nil).formats.count, LectureFormat.builtIn.count)
    }

    func testCodableAndNames() throws {
        let f = LectureFormat(name: "Pomodoro", icon: "timer", rhythm: "20 5 20 15")
        let back = try JSONDecoder().decode(LectureFormat.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
        XCTAssertEqual(LectureFormat.trimName("  A very long name for a lecture format indeed  ").count, LectureFormat.nameLimit)
        XCTAssertEqual(LectureFormat(name: "x", rhythm: "20 5 20").plan.text, "20 5 20 5", "a half-typed rhythm still reads as a plan")
    }
}

final class ShortcutTests: XCTestCase {
    func testRoundTrip() {
        for s in [Shortcut("b", .command), Shortcut("p", [.command, .option]), Shortcut("right"), Shortcut("escape"), Shortcut("+", .command), Shortcut("f5", [.control, .shift])] {
            XCTAssertEqual(Shortcut.decode(s.encode()), s, s.encode())
        }
        XCTAssertEqual(Shortcut("p", [.command, .option]).encode(), "opt+cmd+p")
        XCTAssertNil(Shortcut.decode(""))
        XCTAssertNil(Shortcut.decode("cmd+"))
        XCTAssertNil(Shortcut.decode("meta+b"))
        XCTAssertNil(Shortcut.decode("cmd+bb"))
    }

    func testDisplay() {
        XCTAssertEqual(Shortcut("b", .command).display, "⌘B")
        XCTAssertEqual(Shortcut("right", [.control, .option, .shift, .command]).display, "⌃⌥⇧⌘→")
        XCTAssertEqual(Shortcut("escape").display, "⎋")
    }

    func testUsable() {
        XCTAssertTrue(Shortcut("b", .command).isUsable)
        XCTAssertTrue(Shortcut("f5").isUsable)
        XCTAssertFalse(Shortcut("s").isUsable)
        XCTAssertFalse(Shortcut("s", .shift).isUsable)
    }

    func testDefaultsAreDistinct() {
        let all = ShortcutAction.allCases.compactMap(\.defaultShortcut)
        XCTAssertEqual(Set(all).count, all.count)
        for a in ShortcutAction.allCases { XCTAssertTrue(a.defaultShortcut?.isUsable ?? true, a.title) }
    }

    func testTable() {
        var t = ShortcutTable()
        XCTAssertEqual(t.shortcut(for: .toggleBreak), Shortcut("b", .command))
        t.set(Shortcut("k", .command), for: .toggleBreak)
        XCTAssertEqual(t.shortcut(for: .toggleBreak), Shortcut("k", .command))
        XCTAssertFalse(t.isDefault(.toggleBreak))
        XCTAssertEqual(t.owner(of: Shortcut("k", .command)), .toggleBreak)
        XCTAssertNil(t.owner(of: Shortcut("k", .command), except: .toggleBreak))
        t.set(nil, for: .save)
        XCTAssertNil(t.shortcut(for: .save))
        XCTAssertEqual(t.overrides["save"], "")
        t.set(Shortcut("b", .command), for: .toggleBreak)
        XCTAssertTrue(t.isDefault(.toggleBreak))
        t.reset(.save)
        XCTAssertEqual(t.shortcut(for: .save), Shortcut("s", .command))
    }
}
