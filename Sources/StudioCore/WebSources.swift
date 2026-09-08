import Foundation

/// Sources that start as a URL: a reference course site crawled page by page, a single web page, or a
/// downloadable document. Everything lands as a file under a `sources/` folder, so the rest of the
/// app (listing, indexing, `read_file`) treats it like any other source.
public enum UrlSourceKind: String, CaseIterable, Sendable {
    case referenceCourse, page, document

    public var label: String {
        switch self {
        case .referenceCourse: return "Reference course"
        case .page: return "Web page"
        case .document: return "Document"
        }
    }
    public var help: String {
        switch self {
        case .referenceCourse: return "A course website. Every page under the same folder is fetched (schedule, weeks, readings) and saved as one markdown file with a section per page."
        case .page: return "One page, saved as markdown."
        case .document: return "A file such as a PDF, downloaded as it is."
        }
    }
}

public struct CrawledPage: Sendable {
    public var url: URL
    public var title: String
    public var markdown: String
}

public enum WebSources {
    public static let maxPages = 80
    public static let maxDepth = 3

    public struct FetchError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    static func fetch(_ url: URL) async throws -> (Data, String) {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Mozilla/5.0 (Macintosh) LectureStudio/0.1", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) { throw FetchError(message: "\(url.absoluteString): HTTP \(http.statusCode)") }
        return (data, (http?.value(forHTTPHeaderField: "content-type") ?? "").lowercased())
    }

    // MARK: HTML to markdown (small, regex-based; good enough for retrieval and reading)

    static func decodeEntities(_ s: String) -> String {
        var t = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        t = Rx("&#(\\d+);").replace(t) { g in Int(g[1] ?? "").flatMap { UnicodeScalar($0) }.map { String(Character($0)) } ?? "" }
        t = Rx("&#x([0-9a-fA-F]+);").replace(t) { g in Int(g[1] ?? "", radix: 16).flatMap { UnicodeScalar($0) }.map { String(Character($0)) } ?? "" }
        return t
    }

    public static func htmlToMarkdown(_ html: String, base: URL) -> (title: String, markdown: String) {
        var h = html
        let title = Rx("<title[^>]*>([\\s\\S]*?)</title>", .caseInsensitive).first(h)?[1].map { decodeEntities(Rx("\\s+").replace($0, with: " ")).trimmed } ?? ""
        for tag in ["script", "style", "noscript", "svg", "head", "nav", "footer"] {
            h = Rx("<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", .caseInsensitive).replace(h, with: " ")
        }
        h = Rx("<!--[\\s\\S]*?-->").replace(h, with: "")
        // Block structure first, so line breaks survive the tag stripping.
        h = Rx("<br\\s*/?>", .caseInsensitive).replace(h, with: "\n")
        h = Rx("<h([1-6])[^>]*>", .caseInsensitive).replace(h) { g in "\n\n" + String(repeating: "#", count: Int(g[1] ?? "1") ?? 1) + " " }
        h = Rx("</h[1-6]>", .caseInsensitive).replace(h, with: "\n\n")
        h = Rx("<li[^>]*>", .caseInsensitive).replace(h, with: "\n- ")
        h = Rx("</(p|div|section|article|tr|table|ul|ol|blockquote|pre|header|main|aside|dd|dt)>", .caseInsensitive).replace(h, with: "\n\n")
        h = Rx("<(p|div|section|article|blockquote|header|main|aside|dd|dt)[^>]*>", .caseInsensitive).replace(h, with: "\n")
        h = Rx("</t[dh]>", .caseInsensitive).replace(h, with: " | ")
        h = Rx("<(strong|b)\\b[^>]*>([\\s\\S]*?)</\\1>", .caseInsensitive).replace(h) { g in "**\(g[2] ?? "")**" }
        h = Rx("<(em|i)\\b[^>]*>([\\s\\S]*?)</\\1>", .caseInsensitive).replace(h) { g in "*\(g[2] ?? "")*" }
        h = Rx("<code\\b[^>]*>([\\s\\S]*?)</code>", .caseInsensitive).replace(h) { g in "`\(g[1] ?? "")`" }
        h = Rx("<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>", .caseInsensitive).replace(h) { g in
            let text = Rx("<[^>]+>").replace(g[2] ?? "", with: "").trimmed
            guard !text.isEmpty, let u = URL(string: g[1] ?? "", relativeTo: base)?.absoluteURL else { return text }
            if u.scheme == "javascript" || (g[1] ?? "").hasPrefix("#") { return text }
            return "[\(text)](\(u.absoluteString))"
        }
        h = Rx("<img\\b[^>]*alt=[\"']([^\"']*)[\"'][^>]*>", .caseInsensitive).replace(h) { g in (g[1] ?? "").isEmpty ? "" : "(image: \(g[1]!))" }
        h = Rx("<[^>]+>").replace(h, with: "")
        h = decodeEntities(h)
        h = Rx("[ \\t]+").replace(h, with: " ")
        h = Rx(" *\\n *").replace(h, with: "\n")
        h = Rx("\\n{3,}").replace(h, with: "\n\n")
        return (title, h.trimmed)
    }

    static func links(in html: String, base: URL) -> [URL] {
        var out: [URL] = []
        for m in Rx("<a\\b[^>]*href=[\"']([^\"'#]+)[\"']", .caseInsensitive).all(html) {
            guard let raw = m[1], var u = URL(string: raw, relativeTo: base)?.absoluteURL else { continue }
            u = URL(string: u.absoluteString.components(separatedBy: "#")[0]) ?? u
            out.append(u)
        }
        return out
    }

    /// The default folder the crawl stays inside: the parent of the start page. A schedule page at
    /// `course/spring/schedule/` therefore covers `course/spring/`, where the week pages live.
    public static func scope(of url: URL) -> String {
        let p = (url.path as NSString).deletingLastPathComponent
        return (url.host ?? "") + (p.hasSuffix("/") ? p : p + "/")
    }

    /// Breadth-first crawl of the pages under the start URL's folder, same host. Documents linked from
    /// the pages (PDF and friends) are listed, not downloaded.
    public static func crawlCourse(_ start: URL, scopePrefix: String? = nil, progress: @escaping @Sendable (Int, URL) -> Void = { _, _ in }) async throws -> (pages: [CrawledPage], documents: [URL]) {
        let prefix = (scopePrefix ?? "").isEmpty ? scope(of: start) : scopePrefix!
        var queue: [(URL, Int)] = [(start, 0)]
        var seen: Set<String> = [start.absoluteString]
        var pages: [CrawledPage] = []
        var docs: [URL] = []
        var docSeen: Set<String> = []
        let docExt: Set<String> = ["pdf", "pptx", "ppt", "docx", "doc", "xlsx", "zip", "ipynb"]
        while !queue.isEmpty && pages.count < maxPages {
            let (url, depth) = queue.removeFirst()
            progress(pages.count, url)
            guard let (data, mime) = try? await fetch(url) else { continue }
            guard mime.contains("text/html") || mime.isEmpty, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
            let (title, md) = htmlToMarkdown(html, base: url)
            if !md.isEmpty { pages.append(CrawledPage(url: url, title: title, markdown: md)) }
            guard depth < maxDepth else { continue }
            for link in links(in: html, base: url) {
                let key = link.absoluteString
                let ext = link.pathExtension.lowercased()
                if docExt.contains(ext) {
                    if docSeen.insert(key).inserted { docs.append(link) }
                    continue
                }
                let full = (link.host ?? "") + link.path
                guard link.host == start.host, full.hasPrefix(prefix) || full + "/" == prefix else { continue }
                if seen.insert(key).inserted { queue.append((link, depth + 1)) }
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        if pages.isEmpty { throw FetchError(message: "no readable pages found at \(start.absoluteString)") }
        return (pages, docs)
    }

    /// One markdown file for a crawled course: a header, a table of contents, a section per page.
    public static func courseMarkdown(name: String, start: URL, pages: [CrawledPage], documents: [URL]) -> String {
        var out = "# Reference course: \(name)\n\nSource: \(start.absoluteString)\nFetched: \(Templates.fmtDate())\nPages: \(pages.count)\n\n"
        out += "## Contents\n\n"
        for (i, p) in pages.enumerated() { out += "\(i + 1). [\(p.title.isEmpty ? p.url.lastPathComponent : p.title)](\(p.url.absoluteString))\n" }
        if !documents.isEmpty {
            out += "\n## Linked documents (not downloaded)\n\n"
            for d in documents { out += "- \(d.absoluteString)\n" }
        }
        for p in pages {
            out += "\n\n---\n\n## \(p.title.isEmpty ? p.url.lastPathComponent : p.title)\n\nURL: \(p.url.absoluteString)\n\n\(p.markdown)\n"
        }
        return out
    }

    public static let maxDocuments = 40
    public static let maxDocumentBytes = 40 * 1024 * 1024

    /// Save a URL as source files. Returns the repo paths (a reference course may add the documents it
    /// links to, each as its own file prefixed with the course name). `name` is the file name without extension.
    public static func store(fs: RepoFS, course: String, unit: String, kind: UrlSourceKind, url: URL, name: String, scopePrefix: String? = nil, withDocuments: Bool = true, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> [String] {
        let base = slug(name.isEmpty ? (url.host ?? "web") + "-" + url.lastPathComponent : name)
        switch kind {
        case .referenceCourse:
            let (pages, docs) = try await crawlCourse(url, scopePrefix: scopePrefix) { n, u in progress("Fetched \(n) pages, reading \(u.path)") }
            let md = courseMarkdown(name: name.isEmpty ? url.absoluteString : name, start: url, pages: pages, documents: docs)
            var paths = [try SourceFolders.store(fs: fs, course: course, unit: unit, fileName: "\(base).md", data: Data(md.utf8))]
            if withDocuments {
                // The lecture PDFs of a course site are the material itself; same host only, one file each.
                let own = docs.filter { $0.host == url.host }.prefix(maxDocuments)
                for (i, d) in own.enumerated() {
                    progress("Downloading document \(i + 1) of \(own.count): \(d.lastPathComponent)")
                    guard let (data, _) = try? await fetch(d), data.count <= maxDocumentBytes, !data.isEmpty else { continue }
                    let file = "\(base)--\(slug(d.deletingPathExtension().lastPathComponent)).\(d.pathExtension.lowercased())"
                    if let p = try? SourceFolders.store(fs: fs, course: course, unit: unit, fileName: file, data: data) { paths.append(p) }
                }
            }
            return paths
        case .page:
            progress("Fetching the page")
            let (data, mime) = try await fetch(url)
            if mime.contains("text/html"), let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let (title, body) = htmlToMarkdown(html, base: url)
                let md = "# \(title.isEmpty ? url.absoluteString : title)\n\nSource: \(url.absoluteString)\nFetched: \(Templates.fmtDate())\n\n\(body)\n"
                return [try SourceFolders.store(fs: fs, course: course, unit: unit, fileName: "\(base).md", data: Data(md.utf8))]
            }
            let ext = url.pathExtension.isEmpty ? "txt" : url.pathExtension
            return [try SourceFolders.store(fs: fs, course: course, unit: unit, fileName: "\(base).\(ext)", data: data)]
        case .document:
            progress("Downloading")
            let (data, mime) = try await fetch(url)
            var ext = url.pathExtension
            if ext.isEmpty { ext = mime.contains("pdf") ? "pdf" : mime.contains("html") ? "html" : "bin" }
            return [try SourceFolders.store(fs: fs, course: course, unit: unit, fileName: "\(base).\(ext)", data: data)]
        }
    }
}
