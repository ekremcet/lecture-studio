import Foundation

/// A lecture's rhythm: how long each teaching block runs and how long the break after it lasts, in the order
/// the lecturer teaches them. "20 5 20 15" is twenty minutes on, five off, twenty on, fifteen off.
///
/// The lengths alternate — even entries are blocks, odd entries are the breaks after them — because that is
/// the shape of a lecture and the shape of the text the lecturer types. A plan repeats: when its last break
/// is over the first block starts again, so a three-hour slot keeps its rhythm without being re-armed.
public struct LecturePlan: Equatable, Sendable {
    /// Block, break, block, break…: at least one of each, at most six blocks.
    public private(set) var lengths: [Int]

    /// The rhythm the app starts with: two blocks, the longer break after the second one.
    public static let defaultText = "20 5 20 15"

    public init(_ text: String = LecturePlan.defaultText) {
        var n = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.map(Self.clamp)
        if n.isEmpty { n = [20, 5, 20, 15] }
        if n.count == 1 { n.append(10) }                  // a lone block still needs a break
        if n.count % 2 == 1 { n.append(n[n.count - 2]) }   // a trailing block gets the break before it
        lengths = Array(n.prefix(12))                     // six blocks: a long enough lecture
    }

    /// The lecturer's own limits, in one place: a minute is a minute, and no block runs unseen for hours.
    public static func clamp(_ minutes: Int) -> Int { max(1, min(180, minutes)) }

    /// The lengths as they are kept and edited: "20 5 20 15".
    public var text: String { lengths.map(String.init).joined(separator: " ") }

    /// How a lecturer says it: "20 / 5 · 20 / 15" — a block and the break that follows it.
    public var compact: String {
        stride(from: 0, to: lengths.count, by: 2).map { "\(lengths[$0]) / \(lengths[$0 + 1])" }.joined(separator: " · ")
    }

    /// What the settings pane shows under the field: "teaching 20 min, break 5 min, …".
    public var summary: String {
        lengths.enumerated().map { i, n in "\(i % 2 == 0 ? "teaching" : "break") \(n) min" }.joined(separator: ", ")
    }

    /// One round of the plan in minutes: how long the lecturer teaches before it starts over.
    public var roundMinutes: Int { lengths.reduce(0, +) }

    /// Teaching blocks in one round: what "block 2 of 2" counts.
    public var blocks: Int { lengths.count / 2 }
}

/// A lecture format: a rhythm with the name the lecturer knows it by — "Pomodoro" — and a symbol for the
/// presenter's strip. The lecturer keeps the list in Settings › Teaching and picks one by name in presenter
/// mode; the rhythm text itself is only typed when a format is made or changed.
public struct LectureFormat: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol name, or "" for a format that goes by its name alone.
    public var icon: String
    /// The rhythm as typed: "20 5 20 15". `plan` reads it; a half-typed field is kept as it is.
    public var rhythm: String

    public init(id: UUID = UUID(), name: String, icon: String = "", rhythm: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.rhythm = rhythm
    }

    public var plan: LecturePlan { LecturePlan(rhythm) }

    /// A name fits the strip: one line, and short enough that the rest of the controls keep their room.
    public static let nameLimit = 24
    public static func trimName(_ s: String) -> String { String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit)) }

    /// The formats a new install starts with, the app's own default first.
    public static let builtIn: [LectureFormat] = [
        LectureFormat(name: "Pomodoro", icon: "hourglass", rhythm: LecturePlan.defaultText),
        LectureFormat(name: "Short sprints", icon: "bolt", rhythm: "25 5 25 5 25 5 25 15"),
        LectureFormat(name: "Two halves", icon: "square.split.2x1", rhythm: "45 15 45 15"),
        LectureFormat(name: "One sitting", icon: "book", rhythm: "50 10"),
        LectureFormat(name: "Seminar", icon: "person.2", rhythm: "90 15"),
    ]

    /// The symbols a format can carry, with the word the picker shows for each.
    public static let icons: [(symbol: String, name: String)] = [
        ("hourglass", "Hourglass"), ("timer", "Timer"), ("clock", "Clock"), ("bolt", "Bolt"), ("hare", "Hare"), ("tortoise", "Tortoise"),
        ("book", "Book"), ("graduationcap", "Graduation cap"), ("person.2", "Two people"), ("person.3", "Group"),
        ("bubble.left.and.bubble.right", "Discussion"), ("laptopcomputer", "Laptop"), ("hammer", "Hammer"),
        ("flask", "Flask"), ("lightbulb", "Lightbulb"), ("pencil", "Pencil"), ("square.split.2x1", "Two halves"),
        ("cup.and.saucer", "Cup"), ("figure.walk", "Walk"), ("sun.max", "Sun"), ("moon", "Moon"), ("star", "Star"),
        ("flag", "Flag"), ("leaf", "Leaf"), ("flame", "Flame"),
    ]

    /// The list as it is kept, resolved: what was saved, or — on the first run of this version — the built-in
    /// list with the rhythm the old single "lecturePlan" setting held, so an upgrade keeps the lecturer's
    /// rhythm and its choice. Returns the list and the id of the default format, always one of the list.
    public static func resolve(saved: [LectureFormat]?, defaultId: UUID?, legacyRhythm: String?) -> (formats: [LectureFormat], defaultId: UUID) {
        var list = saved ?? builtIn
        if list.isEmpty { list = builtIn }
        if saved == nil, let legacy = legacyRhythm.map({ LecturePlan($0).text }), !list.contains(where: { $0.plan.text == legacy }) {
            list.append(LectureFormat(name: "My rhythm", icon: "", rhythm: legacy))
        }
        let chosen: UUID
        if let id = defaultId, list.contains(where: { $0.id == id }) {
            chosen = id
        } else if saved == nil, let legacy = legacyRhythm.map({ LecturePlan($0).text }), let hit = list.first(where: { $0.plan.text == legacy }) {
            chosen = hit.id
        } else {
            chosen = list[0].id
        }
        return (list, chosen)
    }
}
