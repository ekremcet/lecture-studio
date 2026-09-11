import Foundation

/// The lecture's clock, pure: it walks a `LecturePlan` — a block counts down, the break after it takes the
/// room (or does not, when the lecturer drives the breaks themselves), and the break's end arms the next
/// block of the plan. Dates in, a tick out — no timers, no windows — so the rhythm is testable, and presenter
/// mode only has to apply what a tick asks for.
///
/// `index` says where in the plan the lecture is: even entries are teaching blocks, odd entries the breaks
/// after them. `until` is nil in three different states, and the flags tell them apart: a clock that is
/// stopped (`running` false), one that is on but waiting out a break (`running`, no `until`), and a block a
/// break interrupted part-way (`pausedLeft`).
public struct LectureCountdown: Equatable, Sendable {
    /// What one tick asks presenter mode to do.
    public enum Tick: Equatable, Sendable {
        case none
        /// The block ran out with auto break on: put the break up on the audience screen for this long.
        case startBreak(minutes: Int)
        /// The block ran out with auto break off: the lecturer takes this one, and presses the key themselves.
        case timeIsUp
    }

    public private(set) var plan: LecturePlan
    /// Where in the plan the lecture is: even entries are blocks, odd ones the breaks after them.
    public private(set) var index = 0
    /// Whether a block that runs out hands the room to its break by itself.
    public var autoBreak: Bool
    /// The lecturer turned the clock on: it walks the plan until they stop it.
    public private(set) var running = false
    /// When the block counting down ends, or nil while the clock is stopped, waiting out a break, or holding
    /// a block that a break interrupted.
    public private(set) var until: Date?
    /// What was left of a block when a break interrupted it, so a stretch mid-block does not cost the block.
    public private(set) var pausedLeft: TimeInterval?

    public init(plan: LecturePlan = LecturePlan(), autoBreak: Bool = true) {
        self.plan = plan
        self.autoBreak = autoBreak
    }

    /// A block is counting down: the countdown the lecturer sees is live.
    public var counting: Bool { running && until != nil }

    /// The teaching block the lecture is on, or the one the current break belongs to.
    public var blockMinutes: Int { plan.lengths[index - index % 2] }
    /// The break that block hands over to.
    public var nextBreakMinutes: Int { plan.lengths[index - index % 2 + 1] }
    /// Which block of the round this is, counting from 1, and how many the round has: "block 2 of 2".
    public var block: Int { index / 2 + 1 }
    public var blocks: Int { plan.blocks }

    /// Arm the clock: this block starts counting down now.
    public mutating func start(now: Date = Date()) {
        running = true
        pausedLeft = nil
        index = index - index % 2          // always on a block: a break is never counted
        until = now.addingTimeInterval(Self.span(plan.lengths[index]))
    }

    /// Stop it: no more blocks on their own. The place in the plan is kept, so the lecturer who stops to
    /// answer a question and starts again picks the lecture up where it was; `reset` is what a new one gets.
    public mutating func stop() {
        running = false
        until = nil
        pausedLeft = nil
    }

    /// A new lecture: the clock off, at the first block of the plan.
    public mutating func reset() {
        stop()
        index = 0
    }

    /// A break took over — the clock's own, or one the lecturer started by hand. The seconds the block had
    /// left are kept.
    public mutating func suspend(now: Date = Date()) {
        if let end = until, end > now { pausedLeft = end.timeIntervalSince(now) }
        until = nil
    }

    /// The break ended: arm the next block, unless the lecturer stopped the clock meanwhile. Returns the new
    /// end, so the caller can show it without waiting for the next tick.
    @discardableResult
    public mutating func resume(now: Date = Date()) -> Date? {
        guard running else { return nil }
        if let left = pausedLeft {
            // A block a break interrupted picks up the seconds it had left.
            pausedLeft = nil
            until = now.addingTimeInterval(left)
            return until
        }
        // The block that ran out is done and this was its break: the next block of the plan starts, and after
        // the last break of the plan the first block starts again.
        index = (index - index % 2 + 2) % plan.lengths.count
        until = now.addingTimeInterval(Self.span(plan.lengths[index]))
        return until
    }

    /// A second has passed — or a test says it has. Reports the block that has just run out, once.
    public mutating func tick(now: Date = Date()) -> Tick {
        guard running, let end = until, now >= end else { return .none }
        until = nil
        pausedLeft = nil
        let b = index - index % 2
        guard autoBreak else {
            // The lecturer takes the breaks themselves: the block is done, and the next start of the clock
            // begins the next block of the plan rather than this one again.
            running = false
            index = (b + 2) % plan.lengths.count
            return .timeIsUp
        }
        index = b + 1                      // the break that follows this block takes the room
        return .startBreak(minutes: plan.lengths[index])
    }

    /// Change the rhythm. The block in progress keeps the end it was given and the blocks after it come from
    /// the new plan; a plan too short to hold the current place wraps instead of leaving the clock off its end.
    public mutating func use(_ plan: LecturePlan) {
        self.plan = plan
        index = index - index % 2
        if index >= plan.lengths.count { index = 0 }
    }

    /// Seconds left in the block, for the countdown the lecturer sees. Nil while no block counts.
    public func secondsLeft(now: Date = Date()) -> Int? {
        guard let end = until else { return nil }
        return max(0, Int(end.timeIntervalSince(now).rounded(.up)))
    }

    private static func span(_ minutes: Int) -> TimeInterval { TimeInterval(LecturePlan.clamp(minutes) * 60) }
}
