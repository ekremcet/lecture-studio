import XCTest
@testable import StudioCore

final class PublishStatusTests: XCTestCase {
    func item(_ unit: Int?, _ path: String, selected: Bool = true) -> PublishItem {
        PublishItem(unit: unit, path: path, source: .repo("c/\(path)"), kind: .deck, size: 1, selected: selected)
    }
    func plan(_ items: [PublishItem]) -> PublishPlan {
        PublishPlan(slug: "c", code: nil, title: "C", term: nil, startDate: nil, weekCount: 3, cancelledDates: [], unitLabel: "Week", topics: [:], items: items, heldBack: [])
    }

    func testStatesAgainstRecord() {
        let p = plan([item(1, "week1-slides.md"), item(1, "week1-slides.pdf"), item(2, "week2-slides.md"), item(3, "week3-slides.md"), item(nil, "syllabus.md"), item(3, "notes.md", selected: false)])
        let record = PublishRecord(slug: "c", url: "u", at: "t", files: ["1/week1-slides.md": "a", "1/week1-slides.pdf": "b", "2/week2-slides.md": "old", "0/syllabus.md": "s"])
        let hashes = ["1/week1-slides.md": "a", "1/week1-slides.pdf": "b", "2/week2-slides.md": "new", "3/week3-slides.md": "x", "0/syllabus.md": "s"]
        let states = PublishStatus.states(plan: p, record: record) { hashes[$0.id] }
        XCTAssertEqual(states[1], .published)
        XCTAssertEqual(states[2], .changed, "hash differs")
        XCTAssertEqual(states[3], .never, "no file of unit 3 in the record")
        XCTAssertEqual(states[0], .published)
    }

    func testNoRecordMeansNever() {
        let states = PublishStatus.states(plan: plan([item(1, "a.md"), item(2, "b.md")]), record: nil) { _ in "x" }
        XCTAssertEqual(states, [1: .never, 2: .never])
    }

    func testNewFileInPublishedUnitIsChanged() {
        let p = plan([item(1, "week1-slides.md"), item(1, "week1-slides.pdf")])
        let record = PublishRecord(slug: "c", url: "u", at: "t", files: ["1/week1-slides.md": "a"])
        let states = PublishStatus.states(plan: p, record: record) { ["1/week1-slides.md": "a", "1/week1-slides.pdf": "b"][$0.id] }
        XCTAssertEqual(states[1], .changed, "the PDF was added after the last publish")
    }
}
