import XCTest
@testable import StudioCore

/// The lecture clock as one state: each transition lands in the case the presenter view expects.
final class LectureCountdownStateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let plan = LecturePlan("20 5 20 15")

    func testEveryTransitionLandsInOneCase() {
        var c = LectureCountdown(plan: plan)
        XCTAssertEqual(c.state, .stopped)
        c.start(now: t0)
        XCTAssertEqual(c.state, .counting(until: t0.addingTimeInterval(1200)))
        c.suspend(now: t0.addingTimeInterval(300))
        XCTAssertEqual(c.state, .interrupted(left: 900))
        // A second break on top of the first keeps the seconds the block had.
        c.suspend(now: t0.addingTimeInterval(400))
        XCTAssertEqual(c.state, .interrupted(left: 900))
        c.resume(now: t0.addingTimeInterval(600))
        XCTAssertEqual(c.state, .counting(until: t0.addingTimeInterval(1500)))
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1500)), .startBreak(minutes: 5))
        XCTAssertEqual(c.state, .onBreak)
        c.stop()
        XCTAssertEqual(c.state, .stopped)
        XCTAssertNil(c.resume(now: t0.addingTimeInterval(1800)), "a stopped clock is not armed by a break's end")
        XCTAssertEqual(c.state, .stopped)
    }

    func testSuspendOnAStoppedClockChangesNothing() {
        var c = LectureCountdown(plan: plan)
        c.suspend(now: t0)
        XCTAssertEqual(c.state, .stopped)
        XCTAssertNil(c.pausedLeft)
    }

    func testSuspendAfterTheEndIsABreakWithNothingToGiveBack() {
        var c = LectureCountdown(plan: plan)
        c.start(now: t0)
        c.suspend(now: t0.addingTimeInterval(1300))
        XCTAssertEqual(c.state, .onBreak)
        XCTAssertTrue(c.running)
        XCTAssertFalse(c.counting)
    }

    func testAutoBreakOffStopsTheClock() {
        var c = LectureCountdown(plan: plan, autoBreak: false)
        c.start(now: t0)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(1200)), .timeIsUp)
        XCTAssertEqual(c.state, .stopped)
    }
}

/// A chat turn: only a running turn holds an approval, questions or a steering note, and late callbacks
/// for a turn that ended (or was replaced) do nothing.
final class ChatTurnStateTests: XCTestCase {
    typealias Turn = ChatTurnState<String, Int>

    func testBeginAndEndOnlyTheirOwnTurn() {
        var t = Turn.idle
        XCTAssertFalse(t.isRunning)
        XCTAssertTrue(t.begin(id: "a", now: Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(t.id, "a")
        XCTAssertEqual(t.started, Date(timeIntervalSince1970: 5))
        XCTAssertFalse(t.begin(id: "b"), "one turn at a time")
        XCTAssertEqual(t.id, "a")
        XCTAssertFalse(t.end(id: "b"), "another turn's end leaves this one running")
        XCTAssertTrue(t.isRunning)
        XCTAssertTrue(t.end(id: "a"))
        XCTAssertEqual(t, .idle)
        XCTAssertFalse(t.end(id: "a"))
    }

    func testPromptsLiveOnlyInsideARunningTurn() {
        var t = Turn.idle
        t.ask(approval: "write file")
        t.ask(question: 1)
        XCTAssertNil(t.approval)
        XCTAssertNil(t.question)
        t.begin(id: "a")
        t.ask(approval: "write file")
        t.ask(question: 7)
        XCTAssertEqual(t.approval, "write file")
        XCTAssertEqual(t.question, 7)
        XCTAssertEqual(t.takeApproval(), "write file")
        XCTAssertNil(t.takeApproval(), "an approval is answered once")
        XCTAssertEqual(t.takeQuestion(), 7)
        XCTAssertNil(t.takeQuestion())
        t.ask(approval: "delete file")
        t.end(id: "a")
        XCTAssertNil(t.approval, "the turn's end takes its prompts with it")
    }

    func testSteeringNoteOneAtATime() {
        var t = Turn.idle
        XCTAssertEqual(t.offerSteer("shorter"), .failure(.notRunning))
        t.begin(id: "a")
        XCTAssertEqual(t.offerSteer("shorter"), .success("a"))
        XCTAssertEqual(t.steer, "shorter")
        XCTAssertEqual(t.offerSteer("again"), .failure(.alreadyPending))
        t.settleSteer(id: "b")
        XCTAssertEqual(t.steer, "shorter", "another turn's answer does not settle this note")
        t.settleSteer(id: "a")
        XCTAssertNil(t.steer)
    }

    func testLateSteerAnswerDoesNotTouchANewerTurn() {
        var t = Turn.idle
        t.begin(id: "a")
        _ = t.offerSteer("note")
        t.end(id: "a")
        t.begin(id: "b")
        _ = t.offerSteer("newer note")
        t.settleSteer(id: "a")
        XCTAssertEqual(t.steer, "newer note")
        XCTAssertEqual(t.id, "b")
    }

    func testClearPromptsKeepsTheTurn() {
        var t = Turn.idle
        t.begin(id: "a")
        t.ask(approval: "x")
        t.ask(question: 1)
        _ = t.offerSteer("s")
        t.clearPrompts()
        XCTAssertEqual(t.id, "a", "the turn runs until its cancel lands")
        XCTAssertNil(t.approval)
        XCTAssertNil(t.question)
        XCTAssertNil(t.steer)
    }
}

/// When the git bar's Pull and Push are off, and why.
final class GitStatusBlockerTests: XCTestCase {
    func testNoUpstreamBlocksBoth() {
        let s = GitStatus(root: "/r", branch: "main", ahead: 2, behind: 3)
        XCTAssertEqual(s.pullBlocker, "No upstream branch")
        XCTAssertEqual(s.pushBlocker, "No upstream branch")
    }

    func testChangesBlockPullAndAskForACommitBeforePush() {
        let s = GitStatus(root: "/r", branch: "main", upstream: "origin/main", behind: 1, changes: [GitChange(status: "M", path: "a.md")])
        XCTAssertEqual(s.pullBlocker, "Commit first, then pull")
        XCTAssertEqual(s.pushBlocker, "Commit first, then push")
    }

    func testCleanAndInSync() {
        let s = GitStatus(root: "/r", branch: "main", upstream: "origin/main")
        XCTAssertEqual(s.pullBlocker, "Nothing to pull")
        XCTAssertEqual(s.pushBlocker, "Nothing to push")
    }

    func testAheadAndBehindCanRun() {
        let s = GitStatus(root: "/r", branch: "main", upstream: "origin/main", ahead: 1, behind: 2)
        XCTAssertNil(s.pullBlocker)
        XCTAssertNil(s.pushBlocker)
    }

    func testOpsSayWhetherToFetchAgain() {
        XCTAssertFalse(GitOp.commit.refetches)
        XCTAssertTrue(GitOp.push.refetches)
        XCTAssertTrue(GitOp.pull.refetches)
    }
}
