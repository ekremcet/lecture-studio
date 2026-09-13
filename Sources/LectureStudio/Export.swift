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

    private(set) var status: ToolStatus = .unknown
    private(set) var busy = false
    private(set) var phase = ""
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

    /// Run marp-cli on `deck` (a file on disk) into `output`. The caller saved the deck first.
    func export(deck: URL, output: URL, options: ExportOptions) async -> Result<ExportReport, ExportError> {
        await probe()
        guard let tool = status.tool else {
            if case .missing(let e) = status { return .failure(e) }
            return .failure(ExportError(.noTool, "marp-cli is not available."))
        }
        guard !busy else { return .failure(ExportError(.failed, "An export is already running.")) }
        busy = true
        phase = tool.source == .npx ? "Starting marp-cli through npx…" : "Converting with \(tool.label)…"
        defer { busy = false; phase = ""; run = nil }
        let themes = WebHost.resource("themes").path
        let browser = AppSettings.browserPath
        return await MarpExporter.run(tool: tool, deck: deck, output: output, options: options, themeDir: themes, browserPath: browser.isEmpty ? nil : browser) { h in
            Task { @MainActor in self.run = h }
        }
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
