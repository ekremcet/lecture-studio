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

    /// A named rhythm the lecturer can pick, in the settings pane and in presenter mode.
    public struct Preset: Identifiable, Sendable {
        public let title: String
        public let text: String
        public var id: String { text }
    }

    /// The rhythms a lecture here actually runs, the app's own default first.
    public static let presets: [Preset] = [
        Preset(title: "20 / 5 · 20 / 15", text: defaultText),
        Preset(title: "25 / 5 ×4, then 15", text: "25 5 25 5 25 5 25 15"),
        Preset(title: "45 / 15 · 45 / 15", text: "45 15 45 15"),
        Preset(title: "50 / 10", text: "50 10"),
        Preset(title: "90 / 15", text: "90 15"),
    ]
}
