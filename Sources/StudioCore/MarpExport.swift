import Foundation

/// Export runs marp-cli on the deck file: the same renderer as the preview, printed by a Chromium
/// browser (or Firefox) into PDF or PowerPoint. Nothing here touches the UI; the app decides where
/// the file goes and shows what happened.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, pptx

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var title: String { self == .pdf ? "PDF" : "PowerPoint" }
}

public struct ExportOptions: Equatable, Sendable {
    public var format: ExportFormat
    /// PDF: the speaker notes as note annotations on each page.
    public var pdfNotes: Bool
    /// PDF: outlines (bookmarks) from slide pages and headings.
    public var pdfOutlines: Bool
    /// PPTX: marp-cli's experimental editable output (needs LibreOffice). Off, every slide is one image
    /// and the notes are kept as speaker notes.
    public var pptxEditable: Bool

    public init(format: ExportFormat = .pdf, pdfNotes: Bool = false, pdfOutlines: Bool = true, pptxEditable: Bool = false) {
        self.format = format
        self.pdfNotes = pdfNotes
        self.pdfOutlines = pdfOutlines
        self.pptxEditable = pptxEditable
    }
}

/// A marp-cli that answered `--version`: how to start it and the PATH it needs (its own folder first, so
/// `#!/usr/bin/env node` finds the node next to it, then the user's shell PATH).
public struct MarpTool: Equatable, Sendable {
    public enum Source: String, Sendable { case custom, shell, known, npxCache, npx }
    public var command: [String]
    public var version: String
    public var source: Source
    public var path: String
    /// The PATH it runs with (see `MarpLocator.environmentPath`).
    public var environmentPath: String

    public init(command: [String], version: String, source: Source, path: String, environmentPath: String) {
        self.command = command
        self.version = version
        self.source = source
        self.path = path
        self.environmentPath = environmentPath
    }

    /// "marp-cli 4.5.1" from marp's own "@marp-team/marp-cli v4.5.1 (w/ @marp-team/marp-core v4.4.0)".
    public var label: String {
        let v = version.split(separator: " ").first { $0.hasPrefix("v") }.map { String($0.dropFirst()) } ?? version.trimmed
        return "marp-cli \(v)"
    }

    /// Where it comes from, for the status line.
    public var origin: String {
        switch source {
        case .custom: "the path in Settings"
        case .shell: "your shell's PATH"
        case .known: path
        case .npxCache: "the npx cache"
        case .npx: "npx (downloaded on first use)"
        }
    }
}

public struct ExportError: LocalizedError, Equatable {
    public enum Kind: Equatable, Sendable { case noTool, noBrowser, noLibreOffice, cancelled, timeout, failed, noOutput }
    public var kind: Kind
    public var message: String
    /// What to do about it, in a sentence.
    public var hint: String?

    public init(_ kind: Kind, _ message: String, hint: String? = nil) {
        self.kind = kind
        self.message = message
        self.hint = hint
    }
    public var errorDescription: String? { message }
}

public struct ExportReport: Equatable, Sendable {
    public var output: URL
    /// marp-cli's warnings worth reading (a missing image, for one), the noise stripped.
    public var warnings: [String]
    public var seconds: Double
}

/// Finds a working marp-cli. A found binary is not a working one: a global install can break with a
/// newer node (its yargs stops loading), so every candidate is asked for `--version` and the first
/// that answers wins.
public enum MarpLocator {
    public struct Candidate: Equatable, Sendable {
        public var command: [String]
        public var source: MarpTool.Source
        public var path: String
    }

    /// The folders a GUI app does not see on its PATH but a terminal does.
    public static func knownDirs(home: String) -> [String] {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.bun/bin", "\(home)/.yarn/bin", "\(home)/Library/pnpm"]
        // Version managers keep one bin folder per node; newest first.
        for base in ["\(home)/.nvm/versions/node", "\(home)/.fnm/node-versions", "\(home)/Library/Application Support/fnm/node-versions"] {
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: base) {
                for v in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                    for sub in ["bin", "installation/bin"] {
                        let d = "\(base)/\(v)/\(sub)"
                        if FileManager.default.isExecutableFile(atPath: "\(d)/node") { dirs.append(d) }
                    }
                }
            }
        }
        return dirs
    }

    /// The candidates in the order they are tried. `shellPath` is the login shell's PATH when it could be read.
    public static func candidates(custom: String?, shellPath: String?, home: String, npxCache: [String] = []) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        func add(_ path: String, _ source: MarpTool.Source, command: [String]? = nil) {
            guard !seen.contains(path), FileManager.default.isExecutableFile(atPath: path) else { return }
            seen.insert(path)
            out.append(Candidate(command: command ?? [path], source: source, path: path))
        }
        if let c = custom?.trimmed, !c.isEmpty {
            // A folder is fine too: the marp inside it.
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: c, isDirectory: &isDir), isDir.boolValue { add("\(c)/marp", .custom) } else { add(c, .custom) }
        }
        for d in (shellPath ?? "").split(separator: ":").map(String.init) where !d.isEmpty { add("\(d)/marp", .shell) }
        for d in knownDirs(home: home) { add("\(d)/marp", .known) }
        for p in npxCache { add(p, .npxCache) }
        // npx itself, last: it downloads marp-cli when the cache has none, which needs the network.
        let dirs = (shellPath ?? "").split(separator: ":").map(String.init) + knownDirs(home: home) + ["/usr/bin", "/bin"]
        if let npx = dirs.map({ "\($0)/npx" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            add(npx, .npx, command: [npx, "--yes", "@marp-team/marp-cli"])
        }
        return out
    }

    /// marp binaries left by earlier `npx @marp-team/marp-cli` runs, newest first.
    public static func npxCache(home: String) -> [String] {
        let base = "\(home)/.npm/_npx"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }
        return dirs.map { "\(base)/\($0)/node_modules/.bin/marp" }
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
            .sorted { a, b in
                let ma = (try? FileManager.default.attributesOfItem(atPath: a)[.modificationDate] as? Date) ?? .distantPast
                let mb = (try? FileManager.default.attributesOfItem(atPath: b)[.modificationDate] as? Date) ?? .distantPast
                return ma > mb
            }
    }

    /// The PATH a marp launch runs with: the binary's folder first (its own node), then the shell's, then the known folders.
    public static func environmentPath(for path: String, shellPath: String?, home: String) -> String {
        var dirs = [(path as NSString).deletingLastPathComponent]
        dirs += (shellPath ?? "").split(separator: ":").map(String.init)
        dirs += knownDirs(home: home) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// The user's PATH as their terminal has it: an interactive login shell prints it. Version managers
    /// (nvm, fnm) live in the rc files, so the shell is interactive too; stdin is closed and the shell is
    /// given five seconds so a prompt cannot hang the app.
    public static func loginShellPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let marker = "__STUDIO_PATH__="
        let r = try? await ProcessRunner.run([shell, "-ilc", "echo \"\(marker)$PATH\""], cwd: nil, environment: nil, timeout: 5)
        guard let r, r.status == 0 else { return nil }
        return r.stdout.split(separator: "\n").last { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)).trimmed }
    }

    /// Ask each candidate for its version; the first that answers is the tool. The last failure is
    /// reported when none does, so a broken install is not mistaken for a missing one.
    public static func find(custom: String?, home: String = NSHomeDirectory()) async -> Result<MarpTool, ExportError> {
        let shellPath = await loginShellPath()
        let list = candidates(custom: custom, shellPath: shellPath, home: home, npxCache: npxCache(home: home))
        var lastFailure: String?
        for c in list {
            let path = environmentPath(for: c.path, shellPath: shellPath, home: home)
            let env = ["PATH": path, "HOME": home, "LANG": "en_US.UTF-8", "NO_COLOR": "1"]
            // npx's first run downloads the package; give it time.
            let r = try? await ProcessRunner.run(c.command + ["--version"], cwd: nil, environment: env, timeout: c.source == .npx ? 120 : 20)
            if let r, r.status == 0, r.stdout.contains("marp") {
                return .success(MarpTool(command: c.command, version: r.stdout.trimmed, source: c.source, path: c.path, environmentPath: path))
            }
            let why = r.map { ProcessRunner.tail($0.stderr.isEmpty ? $0.stdout : $0.stderr) } ?? "did not start"
            lastFailure = "\(c.path): \(why.isEmpty ? "exited with \(r?.status ?? -1)" : why)"
        }
        if let lastFailure {
            return .failure(ExportError(.noTool, "marp-cli was found but does not run.", hint: lastFailure))
        }
        return .failure(ExportError(.noTool, "marp-cli is not installed.", hint: "Install it with `brew install marp-cli` or `npm install -g @marp-team/marp-cli`, or set its path in Settings › Export."))
    }
}

/// The marp-cli export itself.
public enum MarpExporter {
    /// marp's exit codes for the failures worth naming (src/error.ts).
    static let exitNoBrowser: Int32 = 2
    static let exitNoLibreOffice: Int32 = 5

    /// The command line, without the tool. Runs in the deck's folder so `./assets/…` resolves; local
    /// files are always allowed (marp blocks every local image otherwise, even one next to the deck);
    /// the bundled themes come along so `theme: ytu-lecture` renders.
    public static func arguments(input: String, output: String, options: ExportOptions, themeDir: String?, browserPath: String?) -> [String] {
        var args = [input, "--\(options.format.rawValue)"]
        if options.format == .pdf {
            if options.pdfNotes { args.append("--pdf-notes") }
            if options.pdfOutlines { args.append("--pdf-outlines") }
        } else if options.pptxEditable {
            args.append("--pptx-editable")
        }
        args += ["--allow-local-files", "-o", output]
        if let themeDir, !themeDir.isEmpty { args += ["--theme-set", themeDir] }
        if let b = browserPath?.trimmed, !b.isEmpty { args += ["--browser-path", b] }
        return args
    }

    /// marp's stderr, read for what matters: an exit code names the missing browser or LibreOffice;
    /// `[ WARN ]` blocks are kept except the two that say what the options already said.
    public static func interpret(status: Int32, stderr: String, output: URL, seconds: Double) -> Result<ExportReport, ExportError> {
        let blocks = logBlocks(stderr)
        let warnings = blocks.filter { $0.level == "WARN" }.map(\.text).filter { w in
            !w.contains("Insecure local file accessing is enabled") && !w.contains("[EXPERIMENTAL]")
        }
        let errors = blocks.filter { $0.level == "ERROR" }.map(\.text)
        if status == 0 {
            guard FileManager.default.fileExists(atPath: output.path) else {
                return .failure(ExportError(.noOutput, "marp-cli finished but wrote no file.", hint: ProcessRunner.tail(stderr)))
            }
            return .success(ExportReport(output: output, warnings: warnings, seconds: seconds))
        }
        let detail = errors.last ?? ProcessRunner.tail(stderr)
        switch status {
        case exitNoBrowser:
            return .failure(ExportError(.noBrowser, "No browser for the conversion.", hint: "PDF and PowerPoint need Google Chrome, Microsoft Edge, Chromium or Firefox on this Mac; marp-cli finds them on its own. A browser installed elsewhere can be named in Settings › Export."))
        case exitNoLibreOffice:
            return .failure(ExportError(.noLibreOffice, "Editable PowerPoint needs LibreOffice.", hint: "Install LibreOffice (libreoffice.org) or export the plain PowerPoint, which needs only the browser."))
        default:
            return .failure(ExportError(.failed, "marp-cli failed" + (detail.isEmpty ? " (exit \(status))." : ": \(detail)")))
        }
    }

    struct LogBlock: Equatable { var level: String; var text: String }

    /// marp prints `[ LEVEL ] text` with continuation lines indented; joined back into one line each.
    static func logBlocks(_ s: String) -> [LogBlock] {
        var out: [LogBlock] = []
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let level = String(line[line.index(after: line.startIndex)..<close]).trimmed
                out.append(LogBlock(level: level, text: String(line[line.index(after: close)...]).trimmed))
            } else if line.hasPrefix(" "), !out.isEmpty {
                out[out.count - 1].text += " " + line.trimmed
            }
        }
        return out
    }

    /// Run the export. `deck` is the file on disk; `output` is where the file goes (its folder must exist).
    /// `register` receives a handle, so a Cancel button can stop the run.
    public static func run(tool: MarpTool, deck: URL, output: URL, options: ExportOptions, themeDir: String?, browserPath: String?, timeout: TimeInterval = 300, register: (@Sendable (ProcessRunner.Handle) -> Void)? = nil) async -> Result<ExportReport, ExportError> {
        let env = ["PATH": tool.environmentPath, "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "NO_COLOR": "1"]
        let args = arguments(input: deck.lastPathComponent, output: output.path, options: options, themeDir: themeDir, browserPath: browserPath)
        let started = Date()
        do {
            let r = try await ProcessRunner.run(tool.command + args, cwd: deck.deletingLastPathComponent(), environment: env, timeout: timeout, register: register)
            if r.timedOut { return .failure(ExportError(.timeout, "marp-cli did not finish in \(Int(timeout)) seconds.", hint: "The browser may be stuck; try again, or export from a terminal to see what it does.")) }
            if r.cancelled { return .failure(ExportError(.cancelled, "Export cancelled.")) }
            return interpret(status: r.status, stderr: r.stderr, output: output, seconds: Date().timeIntervalSince(started))
        } catch {
            return .failure(ExportError(.failed, "marp-cli could not start: \(error.localizedDescription)"))
        }
    }
}

/// One process, its output collected, a deadline, and a way to stop it from outside.
public enum ProcessRunner {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut: Bool
        public var cancelled: Bool
    }

    /// The running process as the caller sees it: `cancel()` and nothing else. A stop is SIGTERM first,
    /// so a tool that cleans up (marp-cli closes its browser) can, then SIGKILL a few seconds later, so
    /// the run always ends. Cancel is remembered as an intent: a tool that catches SIGTERM exits by code.
    public final class Handle: @unchecked Sendable {
        fileprivate let process: Process
        private let lock = NSLock()
        private var stopped: Stop?
        fileprivate enum Stop { case cancelled, timedOut }

        fileprivate init(_ p: Process) { process = p }

        fileprivate var stop: Stop? { lock.lock(); defer { lock.unlock() }; return stopped }

        public func cancel() { stop(.cancelled) }

        fileprivate func stop(_ why: Stop) {
            lock.lock()
            if stopped == nil { stopped = why }
            lock.unlock()
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [process] in
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    public static func run(_ command: [String], cwd: URL?, environment: [String: String]?, timeout: TimeInterval, register: (@Sendable (Handle) -> Void)? = nil) async throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command[0])
        p.arguments = Array(command.dropFirst())
        p.currentDirectoryURL = cwd
        if let environment { p.environment = environment }
        // marp reads the deck from stdin when stdin is not a terminal: closed, it reads the file.
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let exit = ExitGate()
        // Installed before the launch, so a process that ends at once is not missed.
        p.terminationHandler = { _ in exit.fire() }
        try p.run()
        let handle = Handle(p)
        register?(handle)
        let deadline = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            handle.stop(.timedOut)
        }
        // Drain both pipes off the main thread; a full pipe would otherwise stall the tool.
        async let stdoutData = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let so = await stdoutData
        let se = await stderrData
        await exit.wait()
        deadline.cancel()
        return Result(status: p.terminationStatus, stdout: String(decoding: so, as: UTF8.self), stderr: String(decoding: se, as: UTF8.self), timedOut: handle.stop == .timedOut, cancelled: handle.stop == .cancelled)
    }

    /// The last lines of a tool's output, for a message.
    public static func tail(_ s: String, lines: Int = 4) -> String {
        s.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }.suffix(lines).joined(separator: " ")
    }

    /// The termination, awaited once; firing before the wait is fine.
    private final class ExitGate: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        private var waiter: CheckedContinuation<Void, Never>?

        func fire() {
            lock.lock()
            fired = true
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume()
        }

        func wait() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.lock()
                if fired { lock.unlock(); c.resume(); return }
                waiter = c
                lock.unlock()
            }
        }
    }
}
