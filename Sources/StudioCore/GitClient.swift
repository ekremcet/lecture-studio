import Foundation

public struct GitError: LocalizedError {
    public let message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

/// Human-driven git: status, commit all, push, pull. One operation at a time. Mirrors app/lib/server/git.ts.
public actor GitClient {
    public let root: URL
    public init(root: URL) { self.root = root }

    /// Run git and return stdout; a non-zero exit throws with the last lines of stderr.
    public func run(_ args: [String], timeout: TimeInterval = 60) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "C"
        env["LC_ALL"] = "C"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = env["GIT_SSH_COMMAND"] ?? "ssh -o BatchMode=yes"
        p.environment = env
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let deadline = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if p.isRunning { p.terminate() }
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        deadline.cancel()
        let text = String(decoding: stdout, as: UTF8.self)
        if p.terminationStatus != 0 {
            let e = String(decoding: stderr, as: UTF8.self)
            throw GitError(Self.cleanError(e.isEmpty ? "git \(args.first ?? "") exited with \(p.terminationStatus)" : e))
        }
        return text
    }

    static func cleanError(_ s: String) -> String {
        s.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("Command failed") }.suffix(4).joined(separator: " ")
    }

    public func status(fetchFirst: Bool = false) async throws -> GitStatus {
        var fetchError: String? = nil
        if fetchFirst {
            do { _ = try await run(["fetch", "--quiet"], timeout: 30) } catch { fetchError = error.localizedDescription }
        }
        let branch = try await run(["rev-parse", "--abbrev-ref", "HEAD"]).trimmed
        var upstream: String? = nil
        var ahead = 0
        var behind = 0
        if let up = try? await run(["rev-parse", "--abbrev-ref", "@{upstream}"]).trimmed {
            upstream = up
            let counts = (try? await run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"]).trimmed) ?? ""
            let parts = counts.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
            if parts.count == 2 { ahead = parts[0]; behind = parts[1] }
        }
        let porcelain = try await run(["status", "--porcelain", "--untracked-files=all"])
        let changes = porcelain.split(separator: "\n").filter { !$0.isEmpty }.map { l -> GitChange in
            let line = String(l)
            let st = String(line.prefix(2)).trimmed
            return GitChange(status: st.isEmpty ? "??" : st, path: String(line.dropFirst(3)))
        }
        var last: GitCommitInfo? = nil
        if let log = try? await run(["log", "-1", "--format=%h%x1f%ad%x1f%s", "--date=short"]) {
            let f = log.trimmed.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 3 { last = GitCommitInfo(hash: f[0], date: f[1], subject: f[2]) }
        }
        return GitStatus(root: root.path, branch: branch, upstream: upstream, ahead: ahead, behind: behind, changes: changes, lastCommit: last, fetchError: fetchError)
    }

    public func commitAll(_ message: String) async throws -> (hash: String, files: Int) {
        let msg = message.trimmed
        if msg.isEmpty { throw GitError("commit message is required") }
        _ = try await run(["add", "-A"])
        let staged = try await run(["diff", "--cached", "--name-only"]).split(separator: "\n").filter { !$0.isEmpty }
        if staged.isEmpty { throw GitError("nothing to commit") }
        _ = try await run(["commit", "-q", "-m", msg])
        let hash = try await run(["rev-parse", "--short", "HEAD"]).trimmed
        return (hash, staged.count)
    }

    public func push() async throws -> String {
        let out = try await run(["push", "--porcelain"], timeout: 120).trimmed
        return out.isEmpty ? "pushed" : out
    }

    /// Rebase local commits on the remote. Refuses on a dirty tree, so nothing is stashed behind the user's back.
    public func pull() async throws -> String {
        let dirty = try await run(["status", "--porcelain"]).trimmed
        if !dirty.isEmpty { throw GitError("the working tree has uncommitted changes; commit them first, then pull") }
        let before = try await run(["rev-parse", "HEAD"]).trimmed
        do {
            _ = try await run(["pull", "--rebase", "--quiet"], timeout: 120)
            let after = try await run(["rev-parse", "HEAD"]).trimmed
            if before == after { return "already up to date" }
            let n = try await run(["rev-list", "--count", "\(before)..\(after)"]).trimmed
            return "pulled \(n) commit(s), now at \(after.prefix(7))"
        } catch {
            _ = try? await run(["rebase", "--abort"])
            throw GitError("pull failed and was aborted: \(error.localizedDescription)")
        }
    }

    /// Whether the folder is inside a git work tree at all. Git is optional; a plain folder works.
    public func isRepository() async -> Bool {
        ((try? await run(["rev-parse", "--is-inside-work-tree"]))?.trimmed == "true")
    }

    /// Start tracking a plain folder.
    public func initRepository() async throws {
        _ = try await run(["init", "-q"])
    }

    /// The web page of the repository (GitHub, GitLab, Bitbucket) when the origin remote points at one.
    public func remoteWebURL() async -> URL? {
        guard let raw = try? await run(["remote", "get-url", "origin"]).trimmed, !raw.isEmpty else { return nil }
        var s = raw
        if let m = Rx("^(?:ssh://)?git@([^:/]+)[:/](.+)$").first(s) { s = "https://\(m[1] ?? "")/\(m[2] ?? "")" }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        guard s.hasPrefix("http"), let u = URL(string: s) else { return nil }
        return u
    }

    public func currentBranch() async -> String? {
        (try? await run(["rev-parse", "--abbrev-ref", "HEAD"]))?.trimmed
    }

    public func isTracked(_ path: String) async -> Bool {
        ((try? await run(["ls-files", "--", path]))?.trimmed.isEmpty == false)
    }

    public func move(_ from: String, _ to: String) async throws {
        _ = try await run(["mv", from, to])
    }
}
