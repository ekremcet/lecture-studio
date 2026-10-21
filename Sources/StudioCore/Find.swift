import Foundation

/// The editor's find bar's reading of a search: how many matches the query has, and which one the
/// selection sits on. The counting happens in CodeMirror; the wording lives here so it is testable.
public struct FindStatus: Equatable, Sendable {
    public var count: Int
    /// 1-based; 0 when the selection is not on a match.
    public var current: Int
    /// A regular expression that does not compile.
    public var invalid: Bool
    /// Counting stopped early; there are at least `count` matches.
    public var capped: Bool

    public init(count: Int = 0, current: Int = 0, invalid: Bool = false, capped: Bool = false) {
        self.count = count
        self.current = current
        self.invalid = invalid
        self.capped = capped
    }

    /// "3 of 12", "12 matches", "No matches", "Invalid pattern"; nothing while the field is empty.
    public func label(query: String) -> String {
        if query.isEmpty { return "" }
        if invalid { return "Invalid pattern" }
        if count == 0 { return "No matches" }
        let total = capped ? "\(count)+" : "\(count)"
        if current > 0 { return "\(current) of \(total)" }
        return count == 1 && !capped ? "1 match" : "\(total) matches"
    }
}
