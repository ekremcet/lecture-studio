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
        try fs.writeBytes("cs101-fall26/week1/reading.pdf", Data(repeating: 3, count: 7))
        try fs.writeBytes("cs101-fall26/week1/week1-exam-solutions.pdf", Data(repeating: 4, count: 3))
        try fs.writeBytes("cs101-fall26/syllabus.pdf", Data(repeating: 5, count: 4))
        try fs.writeBytes("cs101-fall26/midterm-1.pdf", Data(repeating: 6, count: 4))
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
        XCTAssertEqual(Set(ids), ["0/midterm-1.pdf", "0/syllabus.pdf", "1/week1-slides.pdf", "1/reading.pdf"], "PDFs only: no decks, images, themes or other documents")
        XCTAssertFalse(ids.contains { $0.contains("sources") || $0.hasSuffix(".md") || $0.hasSuffix(".png") || $0.hasSuffix(".css") })
        XCTAssertEqual(plan.heldBack, ["week1/week1-exam-solutions.pdf"], "only held-back PDFs are worth telling about")
        XCTAssertEqual(plan.decks, [1: "cs101-fall26/week1/week1-slides.md", 2: "cs101-fall26/week2/week2-slides.md"])
        XCTAssertEqual(plan.unitsMissingPdf, [2])
        XCTAssertEqual(plan.items.first { $0.id == "1/week1-slides.pdf" }?.selected, true)
        XCTAssertEqual(plan.items.first { $0.id == "1/reading.pdf" }?.selected, true)
        XCTAssertEqual(plan.items.first { $0.id == "0/syllabus.pdf" }?.selected, true)
        XCTAssertEqual(plan.items.first { $0.id == "0/midterm-1.pdf" }?.selected, false, "course-level PDFs other than the syllabus are offered, not ticked")
        XCTAssertTrue(plan.isDeckPdf(plan.items.first { $0.id == "1/week1-slides.pdf" }!))
        XCTAssertFalse(plan.isDeckPdf(plan.items.first { $0.id == "1/reading.pdf" }!))
        XCTAssertFalse(plan.isDeckPdf(plan.items.first { $0.id == "0/syllabus.pdf" }!))
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
