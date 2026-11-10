import Foundation

/// The lecture's clock, pure: it walks a `LecturePlan` — a block counts down, the break after it takes the
/// room (or does not, when the lecturer drives the breaks themselves), and the break's end arms the next
/// block of the plan. Dates in, a tick out — no timers, no windows — so the rhythm is testable, and presenter
/// mode only has to apply what a tick asks for.
///
/// `index` says where in the plan the lecture is: even entries are teaching blocks, odd entries the breaks
/// after them. `state` says what the clock is doing there, as one value: stopped, counting a block down,
/// waiting out the break after a block that ran out, or holding a block a break interrupted part-way.
/// `running`, `until` and `pausedLeft` are read from it.
public struct LectureCountdown: Equatable, Sendable {
    /// What one tick asks presenter mode to do.
    public enum Tick: Equatable, Sendable {
        case none
        /// The block ran out with auto break on: put the break up on the audience screen for this long.
        case startBreak(minutes: Int)
        /// The block ran out with auto break off: the lecturer takes this one, and presses the key themselves.
        case timeIsUp
    }

    /// What the clock is doing. Each case carries only what it needs, so a stopped clock cannot hold an end
    /// time and a counting one cannot hold paused seconds.
    public enum State: Equatable, Sendable {
        /// Off: no block counts and none starts by itself.
        case stopped
        /// A block is counting down to this end.
        case counting(until: Date)
        /// On, but a break has the room after a block that ran out; its end arms the next block.
        case onBreak
        /// On, but a break interrupted a block part-way; its end gives the block these seconds back.
        case interrupted(left: TimeInterval)
    }

    public private(set) var plan: LecturePlan
    /// Where in the plan the lecture is: even entries are blocks, odd ones the breaks after them.
    public private(set) var index = 0
    /// Whether a block that runs out hands the room to its break by itself.
    public var autoBreak: Bool
    public private(set) var state: State = .stopped

    /// The lecturer turned the clock on: it walks the plan until they stop it.
    public var running: Bool { state != .stopped }
    /// When the block counting down ends, or nil while the clock is stopped, waiting out a break, or holding
    /// a block that a break interrupted.
    public var until: Date? { if case .counting(let end) = state { end } else { nil } }
    /// What was left of a block when a break interrupted it, so a stretch mid-block does not cost the block.
    public var pausedLeft: TimeInterval? { if case .interrupted(let left) = state { left } else { nil } }

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
        index = index - index % 2          // always on a block: a break is never counted
        state = .counting(until: now.addingTimeInterval(Self.span(plan.lengths[index])))
    }

    /// Stop it: no more blocks on their own. The place in the plan is kept, so the lecturer who stops to
    /// answer a question and starts again picks the lecture up where it was; `reset` is what a new one gets.
    public mutating func stop() {
        state = .stopped
    }

    /// A new lecture: the clock off, at the first block of the plan.
    public mutating func reset() {
        stop()
        index = 0
    }

    /// A break took over — the clock's own, or one the lecturer started by hand. The seconds the block had
    /// left are kept.
    public mutating func suspend(now: Date = Date()) {
        // Only a counting block has seconds to keep; a stopped clock, or one already on a break, stays as it is.
        guard case .counting(let end) = state else { return }
        state = end > now ? .interrupted(left: end.timeIntervalSince(now)) : .onBreak
    }

    /// The break ended: arm the next block, unless the lecturer stopped the clock meanwhile. Returns the new
    /// end, so the caller can show it without waiting for the next tick.
    @discardableResult
    public mutating func resume(now: Date = Date()) -> Date? {
        switch state {
        case .stopped:
            return nil
        case .interrupted(let left):
            // A block a break interrupted picks up the seconds it had left.
            let end = now.addingTimeInterval(left)
            state = .counting(until: end)
            return end
        case .onBreak, .counting:
            // The block that ran out is done and this was its break: the next block of the plan starts, and after
            // the last break of the plan the first block starts again.
            index = (index - index % 2 + 2) % plan.lengths.count
            let end = now.addingTimeInterval(Self.span(plan.lengths[index]))
            state = .counting(until: end)
            return end
        }
    }

    /// A second has passed — or a test says it has. Reports the block that has just run out, once.
    public mutating func tick(now: Date = Date()) -> Tick {
        guard case .counting(let end) = state, now >= end else { return .none }
        let b = index - index % 2
        guard autoBreak else {
            // The lecturer takes the breaks themselves: the block is done, and the next start of the clock
            // begins the next block of the plan rather than this one again.
            state = .stopped
            index = (b + 2) % plan.lengths.count
            return .timeIsUp
        }
        index = b + 1                      // the break that follows this block takes the room
        state = .onBreak
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
