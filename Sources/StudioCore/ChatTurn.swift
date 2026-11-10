import Foundation

/// One conversation's turn, as one value: idle, or a turn in flight with what it is waiting on.
///
/// The approval, the question and the steering note only exist inside a running turn, so a conversation
/// cannot show an approval sheet with no turn behind it, and a turn cannot be "running" without the id the
/// bridge streams it under. Every change goes through a transition below; each says when it does nothing,
/// so a late callback (the bridge answering after the turn ended, or after a newer one began) cannot end or
/// change the wrong turn.
///
/// Generic over the approval and question payloads so the rules are testable here without the app's types.
public enum ChatTurnState<Approval: Equatable, Question: Equatable>: Equatable {
    case idle
    case running(Turn)

    public struct Turn: Equatable {
        /// The id the bridge streams this turn's events under.
        public let id: String
        public let started: Date
        /// A tool call waiting for the user's yes or no.
        public var approval: Approval?
        /// Questions the assistant asked, waiting for answers.
        public var question: Question?
        /// A steering note offered to the turn, until a step takes it.
        public var steer: String?

        public init(id: String, started: Date) {
            self.id = id
            self.started = started
        }
    }

    // MARK: reading

    public var isRunning: Bool { if case .running = self { true } else { false } }
    public var turn: Turn? { if case .running(let t) = self { t } else { nil } }
    public var id: String? { turn?.id }
    public var started: Date? { turn?.started }
    public var approval: Approval? { turn?.approval }
    public var question: Question? { turn?.question }
    public var steer: String? { turn?.steer }

    // MARK: transitions

    /// A turn starts. Nothing happens, and false comes back, while another one runs.
    @discardableResult
    public mutating func begin(id: String, now: Date = Date()) -> Bool {
        guard case .idle = self else { return false }
        self = .running(Turn(id: id, started: now))
        return true
    }

    /// The turn `id` ends (done, error, or the send failed). A different or no turn is left alone.
    @discardableResult
    public mutating func end(id: String) -> Bool {
        guard case .running(let t) = self, t.id == id else { return false }
        self = .idle
        return true
    }

    /// The assistant asks for an approval. Ignored when no turn runs.
    public mutating func ask(approval: Approval?) {
        modify { $0.approval = approval }
    }

    /// The assistant asks questions. Ignored when no turn runs.
    public mutating func ask(question: Question?) {
        modify { $0.question = question }
    }

    /// The user answered the approval: it leaves the turn and comes back to be sent, once.
    public mutating func takeApproval() -> Approval? {
        guard let a = approval else { return nil }
        modify { $0.approval = nil }
        return a
    }

    /// The user answered the questions: they leave the turn and come back to be sent, once.
    public mutating func takeQuestion() -> Question? {
        guard let q = question else { return nil }
        modify { $0.question = nil }
        return q
    }

    /// Why a steering note cannot be offered now.
    public enum SteerRefusal: Error, Equatable { case notRunning, alreadyPending }

    /// Offers a steering note to the running turn. Returns the turn id to steer, or why not.
    public mutating func offerSteer(_ text: String) -> Result<String, SteerRefusal> {
        guard case .running(var t) = self else { return .failure(.notRunning) }
        guard t.steer == nil else { return .failure(.alreadyPending) }
        t.steer = text
        self = .running(t)
        return .success(t.id)
    }

    /// The bridge answered the steering note of turn `id`. A no-op once that turn has ended or another began.
    public mutating func settleSteer(id: String) {
        guard case .running(var t) = self, t.id == id else { return }
        t.steer = nil
        self = .running(t)
    }

    /// The transcript was replaced (New, or an archived conversation opened): what waits on the user goes,
    /// the turn itself keeps running until its cancel lands.
    public mutating func clearPrompts() {
        modify { $0.approval = nil; $0.question = nil; $0.steer = nil }
    }

    private mutating func modify(_ fn: (inout Turn) -> Void) {
        guard case .running(var t) = self else { return }
        fn(&t)
        self = .running(t)
    }
}
