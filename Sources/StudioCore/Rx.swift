import Foundation

/// A thin wrapper over NSRegularExpression with JavaScript-like ergonomics, so the ports of the
/// web app's regexes read the same as their TypeScript originals.
public struct Rx {
    public let re: NSRegularExpression

    public init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        // Patterns are literals written in this package; a failure is a programming error.
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    public func test(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Capture groups of the first match; index 0 is the whole match. Missing groups are nil.
    public func first(_ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return String(s[range])
        }
    }

    /// Every match, each as its capture groups.
    public func all(_ s: String) -> [[String?]] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
                return String(s[range])
            }
        }
    }

    public func replace(_ s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Replace each match with the result of a closure over its groups.
    public func replace(_ s: String, _ fn: ([String?]) -> String) -> String {
        var out = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            out += s[last..<whole.lowerBound]
            let groups = (0..<m.numberOfRanges).map { i -> String? in
                let r = m.range(at: i)
                guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
                return String(s[range])
            }
            out += fn(groups)
            last = whole.upperBound
        }
        out += s[last...]
        return out
    }
}

extension String {
    /// JavaScript's `trim()`.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Capitalise the first character only, as the web app's `cap`.
    public var capFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
    /// `s.split("\n")` with JavaScript semantics (keeps empty pieces).
    public var jsLines: [String] { components(separatedBy: "\n") }
}
