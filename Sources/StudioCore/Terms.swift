import Foundation

/// A course over several semesters: a new term is a copy of the last one with the dates moved to the
/// new start date; the old term is archived; the two can be compared unit by unit.
public enum Terms {
    static let iso: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static let dateLine = Rx("(\\*\\*Date:\\*\\*\\s*)(\\d{1,2}\\.\\d{1,2}\\.\\d{4}|DD\\.MM\\.YYYY)")

    public static func isoString(_ d: Date) -> String { iso.string(from: d) }
    public static func isoDate(_ s: String) -> Date? { iso.date(from: s) }

    /// The date of unit `n` (1-based) when the first unit is on `start` and units are weekly.
    public static func unitDate(start: Date, n: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: (n - 1) * 7, to: start) ?? start
    }

    /// Rewrite the `**Date:**` lines of one deck: the first one is the lecture date, any later one
    /// (the "next class" slide) is the following unit's date. Nothing else changes.
    public static func redate(_ markdown: String, unit n: Int, start: Date) -> String {
        var seen = 0
        return dateLine.replace(markdown) { g in
            seen += 1
            let d = unitDate(start: start, n: seen == 1 ? n : n + 1)
            return (g[1] ?? "") + Templates.fmtDate(d)
        }
    }

    public struct NewTermResult: Equatable, Sendable {
        public var course: String
        public var units: [String]
        public var redated: Int
    }

    /// Copy `from` to `folder` as a new term, move the deck dates, write the metadata, optionally archive the old term.
    public static func newTerm(fs: RepoFS, from: String, folder: String, term: String, startDate: Date?, copyUnits: Bool, archiveOld: Bool) async throws -> NewTermResult {
        try Scaffold.checkFolderName(folder)
        if !fs.exists(from) { throw RepoFileError.missing(from) }
        if fs.exists(folder) { throw RepoFileError.exists(folder) }
        let src = try fs.resolve(from)
        let dst = try fs.resolve(folder)
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        var units: [String] = []
        for name in try fm.contentsOfDirectory(atPath: src.path) {
            if name == ".git" || name == ".DS_Store" || name == "node_modules" { continue }
            let isUnit = parseUnit(name) != nil
            if isUnit && !copyUnits { continue }
            // Exported PDFs of the old term do not belong to the new one.
            if name.lowercased().hasSuffix(".pdf") { continue }
            try fm.copyItem(at: src.appendingPathComponent(name), to: dst.appendingPathComponent(name))
            if isUnit { units.append(name) }
        }
        var redated = 0
        if let start = startDate {
            for u in units {
                guard let pu = parseUnit(u) else { continue }
                let deck = "\(folder)/\(u)/\(u)-slides.md"
                guard let text = try? fs.readString(deck) else { continue }
                let updated = redate(text, unit: pu.n, start: start)
                if updated != text { try fs.overwriteText(deck, updated); redated += 1 }
            }
        }
        let store = LectureMetaStore(fs: fs)
        var meta = store.read(from)
        meta.term = term
        meta.derivedFrom = from
        meta.archived = nil
        meta.startDate = startDate.map(isoString)
        try store.write(folder, meta)
        if archiveOld {
            var old = store.read(from)
            old.archived = true
            try store.write(from, old)
        }
        return NewTermResult(course: folder, units: units.sorted(by: Labels.sortUnits), redated: redated)
    }

    public static func setArchived(fs: RepoFS, course: String, _ archived: Bool) throws {
        let store = LectureMetaStore(fs: fs)
        var m = store.read(course)
        m.archived = archived ? true : nil
        try store.write(course, m)
    }
}

/// Line diff and unit-by-unit comparison of two course folders.
public enum Compare {
    public enum Change: String, Sendable { case same, changed, onlyLeft, onlyRight }

    public struct DiffLine: Equatable, Sendable {
        public enum Kind: Sendable { case same, added, removed }
        public var kind: Kind
        public var text: String
    }

    /// Classic LCS over lines; decks are a few thousand lines at most.
    public static func lines(_ a: String, _ b: String) -> [DiffLine] {
        let x = a.jsLines, y = b.jsLines
        let n = x.count, m = y.count
        if n * m > 25_000_000 { return x.map { DiffLine(kind: .removed, text: $0) } + y.map { DiffLine(kind: .added, text: $0) } }
        var dp = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < n && j < m {
            if x[i] == y[j] { out.append(DiffLine(kind: .same, text: x[i])); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { out.append(DiffLine(kind: .removed, text: x[i])); i += 1 }
            else { out.append(DiffLine(kind: .added, text: y[j])); j += 1 }
        }
        while i < n { out.append(DiffLine(kind: .removed, text: x[i])); i += 1 }
        while j < m { out.append(DiffLine(kind: .added, text: y[j])); j += 1 }
        return out
    }

    public struct UnitCompare: Identifiable, Sendable {
        public var unit: String
        public var change: Change
        public var leftDeck: String?
        public var rightDeck: String?
        public var added: Int
        public var removed: Int
        public var id: String { unit }
    }

    /// Units of both courses, with the deck of each unit compared line by line.
    public static func units(fs: RepoFS, left: String, right: String) -> [UnitCompare] {
        func decks(_ c: String) -> [String: String] {
            var out: [String: String] = [:]
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: fs.root.appendingPathComponent(c).path) else { return out }
            for e in entries where parseUnit(e) != nil {
                let p = "\(c)/\(e)/\(e)-slides.md"
                out[e] = fs.exists(p) ? p : ""
            }
            return out
        }
        let l = decks(left), r = decks(right)
        let all = Set(l.keys).union(r.keys).sorted(by: Labels.sortUnits)
        return all.map { u in
            let lp = l[u], rp = r[u]
            if lp == nil { return UnitCompare(unit: u, change: .onlyRight, leftDeck: nil, rightDeck: rp, added: 0, removed: 0) }
            if rp == nil { return UnitCompare(unit: u, change: .onlyLeft, leftDeck: lp, rightDeck: nil, added: 0, removed: 0) }
            let a = (lp ?? "").isEmpty ? "" : (try? fs.readString(lp!)) ?? ""
            let b = (rp ?? "").isEmpty ? "" : (try? fs.readString(rp!)) ?? ""
            if a == b { return UnitCompare(unit: u, change: .same, leftDeck: lp, rightDeck: rp, added: 0, removed: 0) }
            let d = lines(a, b)
            return UnitCompare(unit: u, change: .changed, leftDeck: lp, rightDeck: rp, added: d.filter { $0.kind == .added }.count, removed: d.filter { $0.kind == .removed }.count)
        }
    }
}

/// A term as "Fall 2026": a season and a year, so terms sort and compare without guessing.
public struct TermValue: Equatable, Sendable {
    public static let seasons = ["Spring", "Summer", "Fall", "Winter"]
    public var season: String
    public var year: Int
    public init(season: String, year: Int) { self.season = season; self.year = year }

    public var text: String { "\(season) \(year)" }

    /// Parses "Fall 2026", "fall26", "Güz 2025", "2026 Spring"; nil for anything else.
    public static func parse(_ s: String) -> TermValue? {
        let aliases: [String: String] = ["fall": "Fall", "autumn": "Fall", "guz": "Fall", "güz": "Fall", "spring": "Spring", "bahar": "Spring", "summer": "Summer", "yaz": "Summer", "winter": "Winter", "kis": "Winter", "kış": "Winter"]
        guard let m = Rx("^\\s*(?:([A-Za-zğüşıöçĞÜŞİÖÇ]+)\\s*[- ]?\\s*(\\d{2,4})|(\\d{4})\\s+([A-Za-zğüşıöçĞÜŞİÖÇ]+))\\s*$").first(s) else { return nil }
        let word = (m[1] ?? m[4] ?? "").lowercased(with: Locale(identifier: "tr"))
        guard let season = aliases[word], var year = Int(m[2] ?? m[3] ?? "") else { return nil }
        if year < 100 { year += 2000 }
        return TermValue(season: season, year: year)
    }

    /// Chronological key: year, then the season's place in the year.
    public var order: Int { year * 10 + (Self.seasons.firstIndex(of: season) ?? 0) }

    /// The same season one year on.
    public var next: TermValue { TermValue(season: season, year: year + 1) }
}
