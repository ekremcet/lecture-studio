import XCTest
@testable import StudioCore

final class PublishTests: XCTestCase {
    func makeRepo() throws -> (RepoFS, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("publish-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fs = RepoFS(root: root)
        try fs.mkdir("cs101-fall26/week1/assets")
        try fs.mkdir("cs101-fall26/week2")
        try fs.mkdir("cs101-fall26/sources")
        try fs.createText("cs101-fall26/studio.json", "{\"code\":\"CS101\",\"title\":\"Intro\",\"term\":\"Fall 2026\",\"kind\":\"course\",\"startDate\":\"2026-10-01\",\"weekCount\":12,\"cancelledDates\":[\"2026-10-29\"]}\n")
        try fs.createText("cs101-fall26/syllabus.md", "# Syllabus\n")
        try fs.createText("cs101-fall26/midterm-1-solutions.md", "secret\n")
        try fs.createText("cs101-fall26/week1/week1-slides.md", "---\nmarp: true\ntheme: ytu-lecture\nheader: \"CS101 - Intro\"\nfooter: \"Week 1: Hello\"\n---\n# Hi\n")
        try fs.createText("cs101-fall26/week1/week1-instructor-guide.md", "guide\n")
        try fs.createText("cs101-fall26/week1/notes.md", "plain notes\n")
        try fs.writeBytes("cs101-fall26/week1/week1-slides.pdf", Data(repeating: 1, count: 10))
        try fs.writeBytes("cs101-fall26/week1/assets/fig.png", Data(repeating: 2, count: 5))
        try fs.createText("cs101-fall26/week2/week2-slides.md", "---\nmarp: true\n---\n# Two\n")
        try fs.createText("cs101-fall26/sources/book.pdf", "x")
        return (fs, root)
    }

    func testPlanOffersTheRightFiles() throws {
        let (fs, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let themes = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try "section { color: red }".write(to: themes.appendingPathComponent("ytu-lecture.css"), atomically: true, encoding: .utf8)
        let meta = LectureMetaStore(fs: fs).read("cs101-fall26")
        let plan = Publish.plan(fs: fs, course: "cs101-fall26", meta: meta, courseMeta: courseMeta(fs: fs, course: "cs101-fall26"), themeDirs: [themes])
        XCTAssertEqual(plan.slug, "cs101-fall26")
        XCTAssertEqual(plan.code, "CS101")
        XCTAssertEqual(plan.startDate, "2026-10-01")
        XCTAssertEqual(plan.weekCount, 12)
        XCTAssertEqual(plan.cancelledDates, ["2026-10-29"])
        let ids = plan.items.map(\.id)
        XCTAssertTrue(ids.contains("1/week1-slides.md"))
        XCTAssertTrue(ids.contains("1/week1-slides.pdf"))
        XCTAssertTrue(ids.contains("1/assets/fig.png"))
        XCTAssertTrue(ids.contains("2/week2-slides.md"))
        XCTAssertTrue(ids.contains("0/syllabus.md"))
        XCTAssertTrue(ids.contains("0/themes/ytu-lecture.css"))
        XCTAssertFalse(ids.contains("1/week1-instructor-guide.md"))
        XCTAssertFalse(ids.contains("0/midterm-1-solutions.md"))
        XCTAssertFalse(ids.contains { $0.contains("sources") })
        XCTAssertEqual(plan.heldBack, ["midterm-1-solutions.md", "week1/week1-instructor-guide.md"])
        let notes = plan.items.first { $0.id == "1/notes.md" }
        XCTAssertEqual(notes?.selected, false)
        XCTAssertEqual(notes?.kind, .doc)
        XCTAssertEqual(plan.items.first { $0.id == "1/week1-slides.md" }?.selected, true)
        XCTAssertEqual(plan.items.first { $0.id == "0/syllabus.md" }?.selected, true)
        XCTAssertEqual(plan.topics[1], "Hello")
    }

    func testDeckHeadAndPrivateNames() {
        XCTAssertEqual(Publish.deckHead("---\nmarp: true\ntheme: gaia\n---\n").theme, "gaia")
        XCTAssertTrue(Publish.deckHead("---\nmarp: true\n---\n").marp)
        XCTAssertFalse(Publish.deckHead("# Just markdown\n").marp)
        XCTAssertTrue(Publish.looksPrivate("week3-instructor-guide.md"))
        XCTAssertTrue(Publish.looksPrivate("final_exam_solutions.md"))
        XCTAssertTrue(Publish.looksPrivate(".DS_Store"))
        XCTAssertFalse(Publish.looksPrivate("week3-slides.md"))
        XCTAssertEqual(Publish.slug(for: "YZM2021 Fall26"), "yzm2021-fall26")
    }
}
