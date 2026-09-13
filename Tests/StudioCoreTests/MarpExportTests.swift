import XCTest
@testable import StudioCore

final class MarpExportTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("export-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// A fake executable at `rel` under the temporary home; `script` is what it does.
    @discardableResult
    func fake(_ rel: String, script: String = "#!/bin/sh\necho '@marp-team/marp-cli v9.9.9 (w/ @marp-team/marp-core v4.4.0)'\n") throws -> String {
        let u = home.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return u.path
    }

    func testArguments() {
        let pdf = MarpExporter.arguments(input: "week3-slides.md", output: "/out/week3-slides.pdf", options: ExportOptions(format: .pdf, pdfNotes: true, pdfOutlines: true), themeDir: "/app/themes", browserPath: nil)
        XCTAssertEqual(pdf, ["week3-slides.md", "--pdf", "--pdf-notes", "--pdf-outlines", "--allow-local-files", "-o", "/out/week3-slides.pdf", "--theme-set", "/app/themes"])
        let pptx = MarpExporter.arguments(input: "d.md", output: "/o/d.pptx", options: ExportOptions(format: .pptx, pdfNotes: true, pdfOutlines: true, pptxEditable: true), themeDir: nil, browserPath: " /Applications/Chromium.app/Contents/MacOS/Chromium ")
        XCTAssertEqual(pptx, ["d.md", "--pptx", "--pptx-editable", "--allow-local-files", "-o", "/o/d.pptx", "--browser-path", "/Applications/Chromium.app/Contents/MacOS/Chromium"])
        // PDF options do not leak into a PPTX run and vice versa.
        XCTAssertFalse(MarpExporter.arguments(input: "d.md", output: "d.pptx", options: ExportOptions(format: .pptx, pdfNotes: true), themeDir: nil, browserPath: nil).contains("--pdf-notes"))
        XCTAssertFalse(MarpExporter.arguments(input: "d.md", output: "d.pdf", options: ExportOptions(format: .pdf, pptxEditable: true), themeDir: nil, browserPath: nil).contains("--pptx-editable"))
    }

    func testLogBlocks() {
        let s = """
        [  INFO ] Converting 1 markdown...
        [  WARN ] Insecure local file accessing is enabled for conversion from
                  test-slides.md.
        [  WARN ] The local file is missing and will be ignored. Make sure the file path
                  is correct.
        [ ERROR ] Failed converting Markdown. (LibreOffice soffice binary could not be
                  found.)
        """
        let b = MarpExporter.logBlocks(s)
        XCTAssertEqual(b.map(\.level), ["INFO", "WARN", "WARN", "ERROR"])
        XCTAssertEqual(b[2].text, "The local file is missing and will be ignored. Make sure the file path is correct.")
        XCTAssertEqual(b[3].text, "Failed converting Markdown. (LibreOffice soffice binary could not be found.)")
    }

    func testInterpret() throws {
        let out = home.appendingPathComponent("deck.pdf")
        let stderr = "[  INFO ] Converting 1 markdown...\n[  WARN ] Insecure local file accessing is enabled for conversion from\n          deck.md.\n[  WARN ] The local file is missing and will be ignored. Make sure the file path\n          is correct.\n[  INFO ] deck.md => deck.pdf\n"
        // Exit 0 without a file is a failure, not a success.
        if case .failure(let e) = MarpExporter.interpret(status: 0, stderr: stderr, output: out, seconds: 1) { XCTAssertEqual(e.kind, .noOutput) } else { XCTFail("no file, no failure") }
        try Data("x".utf8).write(to: out)
        guard case .success(let r) = MarpExporter.interpret(status: 0, stderr: stderr, output: out, seconds: 1.5) else { return XCTFail("success expected") }
        XCTAssertEqual(r.warnings, ["The local file is missing and will be ignored. Make sure the file path is correct."])
        XCTAssertEqual(r.output, out)
        guard case .failure(let nb) = MarpExporter.interpret(status: 2, stderr: "[ ERROR ] You have to install Google Chrome...", output: out, seconds: 1) else { return XCTFail() }
        XCTAssertEqual(nb.kind, .noBrowser)
        guard case .failure(let lo) = MarpExporter.interpret(status: 5, stderr: "[ ERROR ] Failed converting Markdown. (LibreOffice soffice binary could not be\n          found.)", output: out, seconds: 1) else { return XCTFail() }
        XCTAssertEqual(lo.kind, .noLibreOffice)
        guard case .failure(let g) = MarpExporter.interpret(status: 1, stderr: "[ ERROR ] Failed converting Markdown. (boom)", output: out, seconds: 1) else { return XCTFail() }
        XCTAssertEqual(g.kind, .failed)
        XCTAssertTrue(g.message.contains("boom"), g.message)
    }

    func testCandidateOrderAndPath() throws {
        let custom = try fake("tools/marp")
        let shell = try fake("shellbin/marp")
        let brew = try fake(".local/bin/marp")
        let cache = try fake(".npm/_npx/abc/node_modules/.bin/marp")
        let npx = try fake("shellbin/npx")
        // The system folders are searched too; a marp installed on this machine is left out of the comparison.
        let list = MarpLocator.candidates(custom: custom, shellPath: "\(home.path)/shellbin:/nowhere", home: home.path, npxCache: MarpLocator.npxCache(home: home.path)).filter { $0.path.hasPrefix(home.path) }
        XCTAssertEqual(list.map(\.path), [custom, shell, brew, cache, npx])
        XCTAssertEqual(list.map(\.source), [.custom, .shell, .known, .npxCache, .npx])
        XCTAssertEqual(list.last?.command, [npx, "--yes", "@marp-team/marp-cli"])
        // A folder as the custom path means the marp inside it; a missing custom path is skipped.
        XCTAssertEqual(MarpLocator.candidates(custom: home.appendingPathComponent("tools").path, shellPath: nil, home: home.path).first?.path, custom)
        XCTAssertNotEqual(MarpLocator.candidates(custom: "/nowhere/marp", shellPath: nil, home: home.path).first?.source, .custom)
        // The launch PATH starts with the binary's own folder, then the shell's, and never repeats.
        let path = MarpLocator.environmentPath(for: brew, shellPath: "\(home.path)/shellbin:/usr/bin", home: home.path).split(separator: ":").map(String.init)
        XCTAssertEqual(path.prefix(2), ["\(home.path)/.local/bin", "\(home.path)/shellbin"])
        XCTAssertEqual(path.filter { $0 == "/usr/bin" }.count, 1)
    }

    /// A found marp that does not run is skipped for the next one; none at all says so.
    func testFindSkipsBrokenTool() async throws {
        try fake(".local/bin/marp", script: "#!/bin/sh\necho 'ReferenceError: require is not defined' >&2\nexit 1\n")
        let good = try fake(".npm/_npx/x/node_modules/.bin/marp")
        let r = await MarpLocator.find(custom: nil, home: home.path)
        guard case .success(let t) = r else { return XCTFail("\(r)") }
        // The shell PATH may hold a real marp on the developer's machine; the fake home's cache is the last resort.
        if t.source == .npxCache { XCTAssertEqual(t.path, good); XCTAssertEqual(t.label, "marp-cli 9.9.9") }
        XCTAssertTrue(t.environmentPath.hasPrefix((t.path as NSString).deletingLastPathComponent))
    }

    func testRunnerClosesStdinAndTimesOut() async throws {
        // `cat` with an open stdin would wait forever; with stdin closed it returns at once.
        let r = try await ProcessRunner.run(["/bin/cat"], cwd: nil, environment: nil, timeout: 5)
        XCTAssertEqual(r.status, 0)
        XCTAssertFalse(r.timedOut)
        let slow = try await ProcessRunner.run(["/bin/sleep", "30"], cwd: nil, environment: nil, timeout: 0.3)
        XCTAssertTrue(slow.timedOut)
        XCTAssertFalse(slow.cancelled)
        let killed = try await ProcessRunner.run(["/bin/sleep", "30"], cwd: nil, environment: nil, timeout: 10) { h in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { h.cancel() }
        }
        XCTAssertTrue(killed.cancelled)
        XCTAssertFalse(killed.timedOut)
        // A tool that catches SIGTERM and exits by code is still a cancel, and one that ignores it is killed.
        let trap = try fake("bin/trap", script: "#!/bin/sh\ntrap 'exit 3' TERM\nwhile true; do sleep 0.1; done\n")
        let caught = try await ProcessRunner.run([trap], cwd: nil, environment: nil, timeout: 10) { h in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { h.cancel() }
        }
        XCTAssertTrue(caught.cancelled)
        XCTAssertEqual(caught.status, 3)
    }
}
