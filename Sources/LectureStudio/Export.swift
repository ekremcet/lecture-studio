import Foundation
import AppKit
import StudioCore

/// The export state the sheet and the toolbar show: which marp-cli was found, whether a run is on,
/// and what the last run said. One export at a time.
@MainActor @Observable
final class Exporter {
    enum ToolStatus: Equatable {
        case unknown, probing, ready(MarpTool), missing(ExportError)
        var tool: MarpTool? { if case .ready(let t) = self { t } else { nil } }
    }

    /// Whether an export runs, and what it is doing. `phase` only exists while one runs.
    enum RunState: Equatable {
        case idle
        case running(phase: String)
    }

    private(set) var status: ToolStatus = .unknown
    private(set) var runState: RunState = .idle
    var busy: Bool { runState != .idle }
    var phase: String { if case .running(let p) = runState { p } else { "" } }
    private var run: ProcessRunner.Handle?
    private var probeTask: Task<Void, Never>?
    private var probeGeneration = 0
    private var settingsTask: Task<Void, Never>?

    /// Find marp-cli (again, after a Settings change or on request). Concurrent callers share one probe;
    /// a forced probe supersedes the running one, whose answer is then dropped.
    func probe(force: Bool = false) async {
        if !force, case .ready = status { return }
        if !force, let t = probeTask { await t.value; return }
        probeGeneration += 1
        let gen = probeGeneration
        status = .probing
        let custom = AppSettings.marpPath
        let t = Task { [weak self] in
            let r = await MarpLocator.find(custom: custom.isEmpty ? nil : custom)
            guard let self, self.probeGeneration == gen else { return }
            switch r {
            case .success(let tool): self.status = .ready(tool)
            case .failure(let e): self.status = .missing(e)
            }
            self.probeTask = nil
        }
        probeTask = t
        await t.value
    }

    /// The Settings changed: forget what was found and look again once typing pauses.
    func settingsChanged() {
        status = .unknown
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.probe(force: true)
        }
    }

    /// Run marp-cli on `deck` (a file on disk) into `output`. The caller saved the deck first. With a
    /// `diagrams` preview, ```mermaid fences are drawn there first and handed to marp-cli as images.
    func export(deck: URL, output: URL, options: ExportOptions, diagrams: PreviewController? = nil) async -> Result<ExportReport, ExportError> {
        await probe()
        guard let tool = status.tool else {
            if case .missing(let e) = status { return .failure(e) }
            return .failure(ExportError(.noTool, "marp-cli is not available."))
        }
        guard !busy else { return .failure(ExportError(.failed, "An export is already running.")) }
        runState = .running(phase: tool.source == .npx ? "Starting marp-cli through npx…" : "Converting with \(tool.label)…")
        defer { runState = .idle; run = nil }
        var input = deck
        var diagramWarnings: [String] = []
        var scratch: [URL] = []
        defer { for u in scratch { try? FileManager.default.removeItem(at: u) } }
        if let preview = diagrams, let text = try? String(contentsOf: deck, encoding: .utf8), Self.mayHaveDiagrams(text) {
            let phase = phase
            runState = .running(phase: "Drawing diagrams…")
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studio-diagrams-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                scratch.append(dir)
                let d = try await preview.exportDiagrams(markdown: text, dir: dir.path)
                diagramWarnings = d.errors
                if !d.files.isEmpty {
                    for f in d.files { try f.svg.write(to: dir.appendingPathComponent(f.name), atomically: true, encoding: .utf8) }
                    // Next to the deck, so its relative assets resolve as they do for the deck itself; removed after the run.
                    let base = (deck.lastPathComponent as NSString).deletingPathExtension
                    let copy = deck.deletingLastPathComponent().appendingPathComponent(".\(base).studio-export.md")
                    try d.markdown.write(to: copy, atomically: true, encoding: .utf8)
                    scratch.append(copy)
                    input = copy
                }
            } catch {
                return .failure(ExportError(.failed, "The Mermaid diagrams could not be prepared: \(error.localizedDescription)"))
            }
            runState = .running(phase: phase)
        }
        let themes = WebHost.resource("themes").path
        let browser = AppSettings.browserPath
        let r = await MarpExporter.run(tool: tool, deck: input, output: output, options: options, themeDir: themes, browserPath: browser.isEmpty ? nil : browser) { h in
            Task { @MainActor in self.run = h }
        }
        return r.map { report in
            var report = report
            report.warnings = diagramWarnings + report.warnings
            return report
        }
    }

    /// A ```mermaid or ~~~mermaid fence somewhere in the deck; the preview's parser decides which are real.
    static func mayHaveDiagrams(_ text: String) -> Bool {
        text.range(of: #"(```|~~~)[ \t]*mermaid"#, options: .regularExpression) != nil
    }

    func cancel() {
        run?.cancel()
    }

    /// What marp-cli will find on its own, for the sheet's status line. A browser elsewhere still works;
    /// marp says so itself when none does.
    static func installedBrowsers() -> [String] {
        let apps = ["Google Chrome", "Microsoft Edge", "Chromium", "Firefox", "Brave Browser", "Google Chrome Canary"]
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        return apps.filter { a in dirs.contains { FileManager.default.fileExists(atPath: "\($0)/\(a).app") } }
    }

    static func libreOfficeInstalled() -> Bool {
        ["/Applications/LibreOffice.app/Contents/MacOS/soffice", NSHomeDirectory() + "/Applications/LibreOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
