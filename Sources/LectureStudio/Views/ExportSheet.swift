import SwiftUI
import AppKit
import UniformTypeIdentifiers
import StudioCore

/// Export the open deck: the format and its options, what marp-cli and browser were found, then the
/// save panel and the run itself, with its outcome in the same sheet.
struct ExportSheet: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var options = AppSettings.exportOptions
    @State private var phase: Phase = .options
    @State private var browsers = Exporter.installedBrowsers()
    @State private var libreOffice = Exporter.libreOfficeInstalled()

    enum Phase: Equatable {
        case options, running, done(ExportReport), failed(ExportError)
    }

    static let pptxType = UTType("org.openxmlformats.presentationml.presentation") ?? .data

    var exporter: Exporter { store.exporter }
    var deckName: String { (store.filePath as NSString).lastPathComponent }
    var outputName: String { ((deckName as NSString).deletingPathExtension) + "." + options.format.fileExtension }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(title: "Export \(deckName)", icon: "square.and.arrow.up", description: "marp-cli renders the deck as the preview shows it and a browser prints it: a PDF, or a PowerPoint with one image per slide and the speaker notes kept.")
            switch phase {
            case .options: optionsBody
            case .running: runningBody
            case .done(let r): doneBody(r)
            case .failed(let e): failedBody(e)
            }
        }
        .dialogFrame(width: 560)
        .interactiveDismissDisabled(phase == .running)
        .task { await exporter.probe() }
    }

    // MARK: options

    @ViewBuilder var optionsBody: some View {
        LabeledField(label: "Format") {
            Picker("", selection: $options.format) {
                ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
        }
        if options.format == .pdf {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Speaker notes as PDF annotations", isOn: $options.pdfNotes)
                Toggle("Outline (bookmarks) from slides and headings", isOn: $options.pdfOutlines)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Editable text and shapes (experimental)", isOn: $options.pptxEditable).disabled(!libreOffice)
                Text(libreOffice
                     ? "Off, each slide is one image and cannot be edited in PowerPoint, but looks exactly like the preview. On, marp-cli rebuilds the slides through LibreOffice; complex themes may come out incomplete."
                     : "Each slide is one image: it looks exactly like the preview but cannot be edited in PowerPoint. Editable output is marp-cli's experimental mode and needs LibreOffice, which is not installed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        toolStatus
        if store.dirty {
            Label(store.staleOnDisk ? "Unsaved edits are saved first. The file also changed on disk; exporting saves your version over it." : "Unsaved edits are saved first: marp-cli reads the file on disk.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            SettingsLink { Text("Settings…") }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Export…") { Task { await run() } }.keyboardShortcut(.defaultAction).disabled(!canExport)
        }
    }

    var canExport: Bool {
        if case .ready = exporter.status, !exporter.busy { return store.canExport }
        return false
    }

    /// What was found: marp-cli (or why not) and the browsers marp-cli will pick from.
    var toolStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                switch exporter.status {
                case .unknown, .probing:
                    ProgressView().controlSize(.small)
                    Text("Looking for marp-cli…").font(.callout).foregroundStyle(.secondary)
                case .ready(let t):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.label).font(.callout)
                        Text(t.source == .known || t.source == .custom ? t.path : "from \(t.origin)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                case .missing(let e):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.message).font(.callout)
                        if let h = e.hint { Text(h).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        HStack {
                            Button("Look again") { Task { await exporter.probe(force: true) } }.controlSize(.small)
                            Button("marp-cli on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/marp-team/marp-cli#install")!) }.controlSize(.small)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: browsers.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(browsers.isEmpty ? .orange : .green)
                Text(browsers.isEmpty
                     ? "No Chrome, Edge, Chromium or Firefox in Applications. marp-cli needs one to print; a browser installed elsewhere can be named in Settings › Export."
                     : "Browser: \(browsers.joined(separator: ", "))" + (AppSettings.browserPath.isEmpty ? "" : " (Settings names \(AppSettings.browserPath))"))
                    .font(.callout).foregroundStyle(browsers.isEmpty ? Color.primary : Color.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: running, done, failed

    var runningBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(exporter.phase.isEmpty ? "Saving…" : exporter.phase).font(.callout)
            }
            Text("The first run starts the browser, which takes a few seconds; npx downloads marp-cli on its first use.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { exporter.cancel() }.keyboardShortcut(.cancelAction)
            }
        }
    }

    func doneBody(_ r: ExportReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exported \(r.output.lastPathComponent)").font(.callout.weight(.medium))
                    Text("\(r.output.deletingLastPathComponent().path) · \(String(format: "%.1f", r.seconds)) s").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if !r.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(r.warnings.enumerated()), id: \.offset) { _, w in
                        Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([r.output]) }
                Button("Open") { NSWorkspace.shared.open(r.output) }
                Spacer()
                Button("Export again…") { phase = .options }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    func failedBody(_ e: ExportError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: e.kind == .cancelled ? "stop.circle" : "xmark.circle.fill").foregroundStyle(e.kind == .cancelled ? Color.secondary : Color.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.message).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let h = e.hint { Text(h).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                }
            }
            HStack {
                if e.kind == .noBrowser || e.kind == .noTool { SettingsLink { Text("Settings…") } }
                if e.kind == .noLibreOffice { Button("LibreOffice") { NSWorkspace.shared.open(URL(string: "https://www.libreoffice.org/download/")!) } }
                Spacer()
                Button("Back") { phase = .options }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: the run

    /// Save if needed, ask where the file goes, run marp-cli, show the outcome.
    func run() async {
        guard let repo = store.repo, store.canExport else { return }
        AppSettings.exportOptions = options
        if store.dirty {
            await store.save()
            // Save shows its own toast when the file cannot be written; nothing to export then.
            guard !store.dirty else { return }
        }
        let deck = repo.root.appendingPathComponent(store.filePath)
        let panel = NSSavePanel()
        panel.title = "Export \(options.format.title)"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [options.format == .pdf ? .pdf : Self.pptxType]
        panel.nameFieldStringValue = outputName
        panel.directoryURL = deck.deletingLastPathComponent()
        guard panel.runModal() == .OK, var output = panel.url else { return }
        // The panel keeps the type, but not always the extension.
        if output.pathExtension.lowercased() != options.format.fileExtension { output.appendPathExtension(options.format.fileExtension) }
        phase = .running
        let r = await exporter.export(deck: deck, output: output, options: options)
        switch r {
        case .success(let report):
            phase = .done(report)
            Task { await store.refreshFiles() }
        case .failure(let e):
            phase = .failed(e)
        }
    }
}
