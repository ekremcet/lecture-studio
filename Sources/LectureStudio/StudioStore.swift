import Foundation
import SwiftUI
import StudioCore

enum Stage { case noRepo, lectures, weeks, work }
enum Dialog: Identifiable { case lecture, talk, editLecture, week, file, sources, profile, importCourse, newTerm, compare, remove, marpHelp; var id: Self { self } }
enum PanelId: String, CaseIterable, Identifiable { case chat, preview, editor; var id: String { rawValue } }
enum SyncSide { case editor, preview }

/// A chat scope: the unit conversation or the whole-course conversation.
struct ChatScope: Identifiable, Equatable {
    var key: String
    var label: String
    var tags: [String]
    var context: String
    var starters: [Starter]
    var hint: String
    var emptyActions: [EmptyAction]
    var id: String { key }
    static func == (a: ChatScope, b: ChatScope) -> Bool { a.key == b.key && a.context == b.context && a.hint == b.hint }
}
struct Starter: Identifiable { var label: String; var prompt: String; var id: String { label } }
struct EmptyAction: Identifiable { var label: String; var icon: String; var dialog: Dialog; var id: String { label } }

/// Document tags per scope. Global sources are searched in every conversation.
func sourceTags(course: String, unit: String) -> (global: String, lecture: String, week: String) {
    ("scope:global", "course:\(course)", "unit:\(course)/\(unit.isEmpty ? "_" : unit)")
}
func scopeTags(course: String, unit: String?) -> [String] {
    let t = sourceTags(course: course, unit: unit ?? "")
    return unit == nil ? [t.global, t.lecture] : [t.global, t.lecture, t.week]
}

/// The whole app state: the repo, what is open, the editor and preview, the agent.
@MainActor @Observable
final class StudioStore {
    static let shared = StudioStore()

    // ---- repo & listing ----
    private(set) var repo: RepoFS?
    var files: [FileInfo] = []
    var lectures: [String: LectureMeta] = [:]
    var filesLoaded = false
    var repoSources = 0
    var profile: Profile?
    var profileExists: Bool?
    /// Git is optional: the bar and the pull/push actions exist only when the folder is a repository.
    var gitAvailable = false
    /// Where the library lives on the web, when git has an origin there (GitHub and the like).
    var remoteWebURL: URL?
    var gitBranch = "main"
    var checklistHidden = AppSettings.checklistHidden
    /// Whether an Oberik project id and key are set. Observable, unlike the defaults and the Keychain behind
    /// it: the Getting started card and the chat's empty state change the moment Settings saves.
    var oberikConfigured = AppSettings.hasOberik
    var refreshKey = 0

    // ---- navigation ----
    var course = ""
    var unit: String? = nil
    var filePath = ""
    var dialog: Dialog?
    /// An image the assistant attached, waiting for the save sheet. On the store, not in a closure passed
    /// down the transcript: a closure is a new value on every render and would invalidate every row.
    var savingAttachment: ChatAttachment?
    /// What the import sheet works on (a folder or a deck file the user picked).
    var importSource: URL?
    var sourceCount = 0

    // ---- open file ----
    var diskText = ""
    var editorText = ""
    var dirty = false
    var staleOnDisk = false
    var slideCount = 0
    var starts: [Int] = [0]
    var qa: QaResult?
    var qaBusy = false
    var previewError: String?
    var current = 0
    var showNotes = AppSettings.showNotes
    /// Presenter mode's defaults, system wide: the lecture formats and the one every lecture starts with,
    /// the break a hand-started Break lasts, and whether a block that runs out hands the room over by itself.
    var lectureFormats: [LectureFormat]
    var lectureFormatId: UUID
    /// The format every lecture starts with, and its rhythm.
    var lectureFormat: LectureFormat { lectureFormats.first { $0.id == lectureFormatId } ?? lectureFormats[0] }
    var lecturePlan: LecturePlan { lectureFormat.plan }
    var lectureBreakMinutes = AppSettings.breakMinutes
    var autoBreak = AppSettings.autoBreak
    var hiddenPanels: Set<PanelId> = Set(AppSettings.hiddenPanels.compactMap(PanelId.init(rawValue:)))
    /// Width of each panel as a share of the workspace; kept per panel, so moving a panel keeps its width.
    var panelFractions: [PanelId: CGFloat] = {
        var out: [PanelId: CGFloat] = [.chat: 0.28, .preview: 0.42, .editor: 0.30]
        for (k, v) in AppSettings.panelFractions { if let id = PanelId(rawValue: k) { out[id] = CGFloat(v) } }
        return out
    }()
    /// Left-to-right order of the workspace panels; the user can move them.
    var panelOrder: [PanelId] = {
        let saved = AppSettings.panelOrder.compactMap(PanelId.init(rawValue:))
        return Set(saved) == Set(PanelId.allCases) ? saved : PanelId.allCases
    }()

    // ---- helpers ----
    let toasts = ToastCenter()
    let preview = PreviewController()
    let editor = EditorController()
    let agent = AgentBridge()
    let presentation = Presentation()
    private var conversations: [String: Conversation] = [:]
    var models: OberikControl.Models?
    var model: String = AppSettings.model
    private var syncLock: (side: SyncSide, until: Date)?
    private var renderTask: Task<Void, Never>?

    init() {
        // The formats list, seeded on the first run of this version from the single rhythm older versions kept.
        let formats = LectureFormat.resolve(saved: AppSettings.lectureFormats, defaultId: AppSettings.lectureFormatId, legacyRhythm: AppSettings.legacyLecturePlan)
        lectureFormats = formats.formats
        lectureFormatId = formats.defaultId
        if AppSettings.lectureFormats == nil { AppSettings.lectureFormats = formats.formats; AppSettings.lectureFormatId = formats.defaultId }
        WebHost.schemeHandler.repo = { [weak self] in self?.repo }
        preview.onVisible = { [weak self] i in self?.onVisibleSlide(i) }
        preview.onRendered = { [weak self] n, s in
            self?.slideCount = n
            self?.starts = s.isEmpty ? [0] : s
        }
        preview.onError = { [weak self] m in self?.previewError = m }
        editor.onChange = { [weak self] text in
            guard let self else { return }
            self.editorText = text
            self.dirty = text != self.diskText
            self.scheduleRender()
        }
        editor.onLine = { [weak self] line, _ in self?.onEditorLine(line) }
        editor.onSave = { [weak self] in Task { await self?.save() } }
        agent.onChat = { [weak self] id, event, d in self?.handleChat(id: id, event: event, d) }
        agent.onUi = { [weak self] name, args in
            guard name == "show_preview", let self else { return }
            self.showPreview(path: args["path"] as? String ?? "", page: args["page"] as? Int)
        }
        agent.toolHandler = { [weak self] name, args in
            guard let self else { throw AgentError("app gone") }
            return try await self.runTool(name, args)
        }
        if let url = AppSettings.defaultRepo() { openRepo(url) }
    }

    // MARK: repo

    var stage: Stage {
        if repo == nil { return .noRepo }
        if course.isEmpty { return .lectures }
        if unit == nil { return .weeks }
        return .work
    }

    /// Reports changes made to the library outside the app (see FolderWatcher).
    @ObservationIgnored private var watcher: FolderWatcher?

    func openRepo(_ url: URL) {
        repo = RepoFS(root: url)
        watcher?.stop()
        watcher = FolderWatcher(root: url) { [weak self] paths in self?.externalChanges(paths) }
        watcher?.start()
        AppSettings.repoPath = url.path
        course = ""
        unit = nil
        filePath = ""
        files = []
        filesLoaded = false
        conversations = [:]
        Task { await refreshFiles() }
        Task { await loadProfile() }
        Task { await checkGit() }
        if models == nil, AppSettings.hasOberik { Task { await loadModels() } }
        // Land where the user left off: the open file, else the unit or course screen.
        let last = AppSettings.lastFile
        let lastCourse = AppSettings.lastCourse
        let lastUnit = AppSettings.lastUnit
        Task {
            await refreshFiles()
            if !last.isEmpty, files.contains(where: { $0.path == last }) {
                await openFile(last, select: true)
            } else if !lastCourse.isEmpty, files.contains(where: { $0.course == lastCourse }) {
                course = lastCourse
                unit = lastUnit.flatMap { u in files.contains { $0.course == lastCourse && $0.unit == u } ? u : nil }
                await refreshSourceCount()
            }
        }
    }

    private func rememberPlace() {
        AppSettings.lastCourse = course
        AppSettings.lastUnit = unit
        AppSettings.lastFile = stage == .work ? filePath : ""
    }

    func checkGit() async {
        guard let fs = repo else { gitAvailable = false; remoteWebURL = nil; return }
        let git = GitClient(root: fs.root)
        gitAvailable = await git.isRepository()
        remoteWebURL = gitAvailable ? await git.remoteWebURL() : nil
        gitBranch = (gitAvailable ? await git.currentBranch() : nil) ?? "main"
    }

    /// The course folder on the remote's website, e.g. GitHub's tree view.
    func webURL(forCourse c: String) -> URL? {
        guard let base = remoteWebURL else { return nil }
        let host = base.host ?? ""
        let seg = host.contains("gitlab") ? "-/tree" : host.contains("bitbucket") ? "src" : "tree"
        return base.appendingPathComponent("\(seg)/\(gitBranch)/\(c)")
    }

    /// Start tracking the open folder with git.
    func initGit() async {
        guard let fs = repo else { return }
        do {
            try await GitClient(root: fs.root).initRepository()
            await checkGit()
            toasts.success("Git initialized", fs.root.lastPathComponent)
        } catch { toasts.error("Could not initialize git", error) }
    }

    /// Changes on disk that did not come from this app: the file list, the profile, the git state and,
    /// when it is the open file, the editor (or a "reload" notice when there are unsaved edits).
    private func externalChanges(_ paths: [String]) {
        Task { await refreshFiles() }
        if paths.contains(where: { $0 == "studio.json" }) { Task { await loadProfile() } }
        if !filePath.isEmpty, paths.contains(where: { $0 == filePath || filePath.hasPrefix($0 + "/") }) {
            if dirty { staleOnDisk = true } else { Task { await openFile(filePath, select: false) } }
        }
        if gitAvailable { Task { await checkGit() } }
    }

    /// The Refresh button and ⌘R: everything the watcher would report, on demand.
    func refreshLibrary() async {
        await refreshFiles()
        await loadProfile()
        if gitAvailable { await checkGit() }
        if !filePath.isEmpty {
            if dirty { staleOnDisk = (try? repo?.readString(filePath)) != editorText } else { await openFile(filePath, select: false) }
        }
    }

    func refreshFiles() async {
        guard let fs = repo else { return }
        let idx = await Task.detached { FilesIndex.scan(fs: fs) }.value
        files = idx.files
        lectures = idx.lectures
        repoSources = idx.sources
        filesLoaded = true
        refreshKey += 1
        await refreshSourceCount()
    }

    func loadProfile() async {
        guard let fs = repo else { return }
        let store = ProfileStore(fs: fs)
        if store.exists() {
            profile = store.read()
            profileExists = true
        } else {
            profile = await store.suggested()
            profileExists = false
        }
    }

    /// After Settings saves: the flag the views watch, the agent page, the model list.
    func oberikSettingsChanged() {
        oberikConfigured = AppSettings.hasOberik
        agent.load()
        Task { await loadModels() }
    }

    func loadModels() async {
        guard AppSettings.hasOberik else { return }
        let c = OberikControl(projectId: AppSettings.projectId, projectKey: AppSettings.projectKey)
        models = try? await c.models()
    }

    func refreshSourceCount() async {
        guard let fs = repo, !course.isEmpty else { sourceCount = 0; return }
        let c = course == "(root)" ? "" : course
        let u = unit ?? ""
        sourceCount = await Task.detached { SourceFolders.sources(fs: fs, course: c, unit: u).count }.value
    }

    // MARK: derived

    var meta: LectureMeta? { lectures[course] }
    var talk: Bool { Labels.isTalk(meta) }
    var word: String { Labels.unitWord(meta, units: files.filter { $0.course == course }.map(\.unit).filter { !$0.isEmpty }) }
    var kind: FileKind { files.first { $0.path == filePath }?.kind ?? (filePath.hasSuffix(".md") ? .deck : .other) }
    var isDeck: Bool { kind == .deck }
    var isText: Bool { TEXT_KINDS.contains(kind) }
    var previewText: String { dirty ? editorText : diskText }
    var unitFiles: [FileInfo] { files.filter { $0.course == course && $0.unit == (unit ?? "") } }
    var notes: [String] { isDeck && showNotes ? Slides.notes(previewText, starts: starts, index: current) : [] }
    var hasCourse: Bool { files.contains { $0.course != "(root)" } }
    var checklist: GettingStartedState? {
        guard filesLoaded, let pe = profileExists else { return nil }
        let s = GettingStartedState(profile: pe, course: hasCourse, sources: repoSources > 0, assistant: oberikConfigured)
        if checklistHidden || (s.profile && s.course && s.sources && s.assistant) { return nil }
        return s
    }

    func selectCourse(_ c: String) {
        course = c
        unit = nil
        rememberPlace()
        Task { await refreshSourceCount() }
    }

    func openUnit(_ u: String, path: String) {
        unit = u
        rememberPlace()
        Task {
            await refreshSourceCount()
            await openFile(path, select: false)
        }
    }

    func backToUnits() { unit = nil; rememberPlace(); Task { await refreshSourceCount() } }
    func backToLectures() { course = ""; unit = nil; sourceCount = 0; rememberPlace() }

    /// Every term of the same course: folders linked by `derivedFrom` in either direction, newest first.
    func terms(of c: String) -> [String] {
        var set: Set<String> = [c]
        var changed = true
        while changed {
            changed = false
            for (folder, meta) in lectures {
                if let from = meta.derivedFrom, (set.contains(from) && !set.contains(folder)) || (set.contains(folder) && !set.contains(from)) {
                    set.insert(folder); set.insert(from); changed = true
                }
            }
        }
        // Oldest first: follow derivedFrom depth, then the term text.
        func depth(_ f: String) -> Int { var d = 0; var cur = f; var seen: Set<String> = []; while let from = lectures[cur]?.derivedFrom, seen.insert(cur).inserted { d += 1; cur = from }; return d }
        let present = Set(files.map(\.course))
        func key(_ f: String) -> (Int, Int, String) { (TermValue.parse(lectures[f]?.term ?? "")?.order ?? 0, depth(f), lectures[f]?.term ?? f) }
        return set.filter { present.contains($0) }.sorted { key($0) > key($1) }
    }

    /// Move a course or talk folder to the Trash (recoverable there). Also drops it from the hidden list.
    func trashCourse(_ c: String) {
        guard let fs = repo, let u = try? fs.resolve(c) else { return }
        do {
            try FileManager.default.trashItem(at: u, resultingItemURL: nil)
            try? ProfileStore(fs: fs).setExcluded(c, false)
            toasts.success("Moved to Trash", c)
            if course == c { backToLectures() }
            Task { await refreshFiles() }
        } catch { toasts.error("Could not move the folder to the Trash", error) }
    }

    /// Hide a top-level folder that is neither a course nor a talk (or show it again).
    func setExcluded(_ name: String, _ excluded: Bool) {
        guard let fs = repo else { return }
        do {
            try ProfileStore(fs: fs).setExcluded(name, excluded)
            profile = ProfileStore(fs: fs).read()
            toasts.success(excluded ? "Hidden from the studio" : "Shown again", name)
            if excluded && course == name { backToLectures() }
            Task { await refreshFiles() }
        } catch { toasts.error("Could not update the library settings", error) }
    }

    /// Switch a folder between a course (numbered units) and a talk (one deck).
    func setKind(_ c: String, _ kind: LectureKind) {
        guard let fs = repo else { return }
        do {
            let store = LectureMetaStore(fs: fs)
            var m = store.read(c)
            m.kind = kind
            if m.title == nil { m.title = Labels.courseTitle(c) }
            try store.write(c, m)
            toasts.success(kind == .talk ? "Now a talk" : "Now a course", Labels.courseLabel(c, m))
            Task { await refreshFiles() }
        } catch { toasts.error("Could not change the type", error) }
    }

    func setArchived(_ c: String, _ archived: Bool) {
        guard let fs = repo else { return }
        do {
            try Terms.setArchived(fs: fs, course: c, archived)
            toasts.success(archived ? "Archived" : "Unarchived", Labels.courseLabel(c, lectures[c]))
            Task { await refreshFiles() }
        } catch { toasts.error("Could not update the course", error) }
    }

    func dismissChecklist() {
        checklistHidden = true
        AppSettings.checklistHidden = true
    }

    // MARK: files

    func openFile(_ path: String, select: Bool) async {
        guard let fs = repo else { return }
        let k = files.first { $0.path == path }?.kind ?? (path.hasSuffix(".md") ? .md : .other)
        var text = ""
        if TEXT_KINDS.contains(k) || path.hasSuffix(".md") {
            do { text = try fs.readString(path) } catch {
                toasts.error("Could not open the file", error)
                return
            }
        }
        filePath = path
        diskText = text
        editorText = text
        dirty = false
        staleOnDisk = false
        qa = nil
        current = 0
        previewError = nil
        if select {
            let segs = path.split(separator: "/").map(String.init)
            course = segs.count > 1 ? segs[0] : "(root)"
            unit = segs.count > 2 ? segs[1] : ""
            await refreshSourceCount()
        }
        rememberPlace()
        editor.setValue(text, plain: k == .text)
        renderNow()
    }

    func save() async {
        guard let fs = repo, !filePath.isEmpty, dirty else { return }
        do {
            try fs.overwriteText(filePath, editorText)
            diskText = editorText
            dirty = false
            staleOnDisk = false
            toasts.success("Saved", filePath)
            await refreshFiles()
        } catch {
            toasts.error("Save failed", error)
        }
    }

    func reloadFromDisk() { Task { await openFile(filePath, select: false) } }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.renderNow()
        }
    }

    func renderNow() {
        let text = previewText
        let dir = deckDir(filePath)
        let k = kind
        Task {
            if k == .deck {
                await preview.render(markdown: text, deckDir: dir)
            } else if k == .md || k == .text {
                await preview.renderDocument(markdown: text, deckDir: dir, plain: k == .text)
            }
        }
    }

    // MARK: scroll sync (500 ms lock)

    func goToSlide(_ index: Int, from: String) {
        current = index
        let now = Date()
        if from != "preview" {
            syncLock = (.preview, now.addingTimeInterval(0.5))
            preview.scrollTo(page: index + 1, smooth: from == "rail")
        }
        if from != "editor" {
            syncLock = (.editor, now.addingTimeInterval(0.5))
            editor.scrollToLine(index < starts.count ? starts[index] : 0)
        }
        if from == "rail" { syncLock = (.preview, now.addingTimeInterval(0.7)) }
    }

    private func onEditorLine(_ line: Int) {
        guard isDeck else { return }
        if let l = syncLock, l.side == .editor, Date() < l.until { return }
        let idx = Slides.slideForLine(starts, line)
        if idx != current { goToSlide(idx, from: "editor") }
    }

    private func onVisibleSlide(_ idx: Int) {
        if let l = syncLock, l.side == .preview, Date() < l.until { return }
        if idx != current { goToSlide(idx, from: "preview") }
    }

    func runQa() async {
        guard isDeck else { return }
        qaBusy = true
        defer { qaBusy = false }
        do { qa = try await preview.scan() } catch { toasts.error("Check failed", error) }
    }

    /// Only a deck that is open in the workspace can be presented.
    var canPresent: Bool { stage == .work && isDeck && !filePath.isEmpty }

    /// Presenter mode: slides on the second screen, notes and the next slide on this one.
    func startPresentation() {
        guard canPresent else { return }
        presentation.start(store: self, from: current)
    }

    func togglePanel(_ p: PanelId) {
        var next = hiddenPanels
        if next.contains(p) { next.remove(p) } else { next.insert(p) }
        if next.count == PanelId.allCases.count { return }
        hiddenPanels = next
        AppSettings.hiddenPanels = next.map(\.rawValue)
    }

    func movePanel(_ p: PanelId, by dir: Int) {
        guard let i = panelOrder.firstIndex(of: p) else { return }
        let j = i + dir
        guard j >= 0, j < panelOrder.count else { return }
        panelOrder.swapAt(i, j)
        AppSettings.panelOrder = panelOrder.map(\.rawValue)
    }

    func resetLayout() {
        panelOrder = PanelId.allCases
        hiddenPanels = []
        panelFractions = [.chat: 0.28, .preview: 0.42, .editor: 0.30]
        AppSettings.panelOrder = []
        AppSettings.hiddenPanels = []
        AppSettings.panelFractions = [:]
    }

    func savePanelFractions() {
        AppSettings.panelFractions = Dictionary(uniqueKeysWithValues: panelFractions.map { ($0.key.rawValue, Double($0.value)) })
    }

    func toggleNotes() {
        showNotes.toggle()
        AppSettings.showNotes = showNotes
    }

    // MARK: the lecture clock's defaults

    /// The lecture formats, as Settings › Teaching edits them. Names are trimmed to what the strip can show;
    /// an emptied list gets the built-in one back, and the default follows a format that was removed.
    func setLectureFormats(_ list: [LectureFormat]) {
        var list = list.map { f in var f = f; f.name = LectureFormat.trimName(f.name); return f }
        if list.isEmpty { list = LectureFormat.builtIn }
        lectureFormats = list
        if !list.contains(where: { $0.id == lectureFormatId }) { lectureFormatId = list[0].id }
        AppSettings.lectureFormats = list
        AppSettings.lectureFormatId = lectureFormatId
    }

    /// The format every lecture starts with. Presenter mode can run another one for a single lecture
    /// without coming back here.
    func setLectureFormat(_ id: UUID) {
        guard lectureFormats.contains(where: { $0.id == id }) else { return }
        lectureFormatId = id
        AppSettings.lectureFormatId = id
    }

    /// How long a break the lecturer starts by hand lasts.
    func setLectureBreakMinutes(_ n: Int) {
        lectureBreakMinutes = LecturePlan.clamp(n)
        AppSettings.breakMinutes = lectureBreakMinutes
    }

    func setAutoBreak(_ on: Bool) {
        autoBreak = on
        AppSettings.autoBreak = on
    }

    // MARK: agent tool host (the client tools declared in web-core/src/shared/tools.ts)

    private func onFileChanged(_ path: String) {
        Task { await refreshFiles() }
        if path != filePath {
            if filePath.isEmpty && path.hasSuffix(".md") { Task { await openFile(path, select: false) } }
            return
        }
        if dirty { staleOnDisk = true } else { Task { await openFile(path, select: false) } }
    }

    private func showPreview(path: String, page: Int?) {
        let go = { [weak self] in if let page { self?.goToSlide(page - 1, from: "rail") } }
        if path != filePath {
            Task {
                await openFile(path, select: false)
                try? await Task.sleep(nanoseconds: 700_000_000)
                go()
            }
        } else { go() }
    }

    private func qaDeck(_ path: String) async throws -> QaResult {
        guard let fs = repo else { throw AgentError("no repo") }
        let text = try fs.readString(path)
        if path != filePath {
            await openFile(path, select: false)
        } else {
            diskText = text
            if !dirty { editorText = text; editor.setValue(text, plain: false) } else { staleOnDisk = true }
        }
        await preview.render(markdown: text, deckDir: deckDir(path))
        let r = try await preview.scan()
        qa = r
        return r
    }

    /// Source files with their index status, for `list_sources` and the sources sheet.
    func sourceRows(course c: String, unit u: String?) async -> (rows: [SourceRow], indexError: String?) {
        guard let fs = repo else { return ([], nil) }
        let tags = scopeTags(course: c, unit: u)
        let disk = await Task.detached { SourceFolders.sources(fs: fs, course: c, unit: u ?? "") }.value
        var docs: [OberikDocument] = []
        var indexError: String?
        if AppSettings.hasOberik {
            do { docs = try await agent.listDocuments(tags: tags) } catch { indexError = error.localizedDescription }
        } else {
            indexError = "Oberik is not configured; open Settings."
        }
        let t = sourceTags(course: c, unit: u ?? "")
        var byPath: [String: OberikDocument] = [:]
        for d in docs { if let p = d.tags.first(where: { $0.hasPrefix("path:") }) { byPath[String(p.dropFirst(5))] = d } }
        var used = Set<String>()
        var rows: [SourceRow] = disk.map { f in
            let d = byPath[f.path]
            if let d { used.insert(d.id) }
            return SourceRow(key: f.path, name: f.name, path: f.path, scope: f.scope, doc: d, size: f.size)
        }
        for d in docs where !used.contains(d.id) {
            let scope: SourceScope = d.tags.contains(t.week) ? .unit : d.tags.contains(t.lecture) ? .lecture : .global
            rows.append(SourceRow(key: d.id, name: d.filename, path: d.tags.first { $0.hasPrefix("path:") }.map { String($0.dropFirst(5)) }, scope: scope, doc: d, size: nil))
        }
        return (rows, indexError)
    }

    private func runTool(_ name: String, _ args: [String: Any]) async throws -> Any {
        guard let fs = repo else { throw AgentError("no repository open") }
        func str(_ k: String) -> String { (args[k] as? String) ?? (args[k].map { "\($0)" } ?? "") }
        func num(_ k: String) -> Int? { args[k] as? Int ?? Int(str(k)) }
        switch name {
        case "list_dir":
            let p = str("path").isEmpty ? "." : str("path")
            return encodeBridge(try fs.listDir(p))
        case "read_file":
            return encodeBridge(try fs.readText(str("path"), from: num("from"), to: num("to")))
        case "create_file":
            try fs.createText(str("path"), str("content"))
            onFileChanged(str("path"))
            return ["ok": true, "path": str("path"), "created": true]
        case "overwrite_file":
            try fs.overwriteText(str("path"), str("content"))
            onFileChanged(str("path"))
            return ["ok": true, "path": str("path"), "overwritten": true]
        case "append_file":
            try fs.appendText(str("path"), str("content"))
            onFileChanged(str("path"))
            return ["ok": true, "path": str("path"), "appended": str("content").count]
        case "replace_in_file":
            let line = try fs.replaceOnce(str("path"), old: str("old"), new: str("new"))
            onFileChanged(str("path"))
            return ["ok": true, "path": str("path"), "line": line]
        case "save_asset":
            let s = try await Assets.save(fs: fs, weekDir: str("week_dir"), filename: str("filename"), source: str("source"))
            onFileChanged(s.path)
            return encodeBridge(s)
        case "list_sources":
            let c = course == "(root)" ? "" : course
            let (rows, _) = await sourceRows(course: c, unit: unit)
            return rows.map { r -> [String: Any] in
                var o: [String: Any] = ["name": r.name, "scope": r.scope.rawValue, "status": r.doc?.status ?? "on disk, not indexed (ask the user to press Index in Sources)"]
                if let p = r.path { o["path"] = p }
                return o
            }
        case "qa_deck":
            return try await qaDeck(str("path")).compact
        default:
            throw AgentError("unknown tool \(name)")
        }
    }

    // MARK: chat

    /// The conversation of a scope. The first time a scope is asked for, the newest archived conversation
    /// of that scope comes back (its session continues); before the archive existed the session id lived in
    /// the defaults, and that still seeds a conversation with no archive.
    func conversation(_ key: String) -> Conversation {
        if let c = conversations[key] { return c }
        let c = Conversation(key: key)
        if let a = archive?.latest(scope: key) { c.restore(a) } else { c.sessionId = AppSettings.sessionId(for: key) }
        conversations[key] = c
        return c
    }

    /// The chat archive of the open library folder. `STUDIO_CHAT_ARCHIVE=/dir` moves it (smoke runs keep
    /// their synthetic conversations out of the real history).
    var archive: ChatArchive? {
        repo.map { ChatArchive.forRepo($0.root, base: ProcessInfo.processInfo.environment["STUDIO_CHAT_ARCHIVE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) }
    }

    /// Writes the conversation to the archive; empty conversations are not kept.
    func saveConversation(_ conv: Conversation) {
        guard !conv.messages.isEmpty, let archive else { return }
        conv.updated = Date()
        do { try archive.save(conv.archived()) } catch { toasts.error("Could not save the conversation", error) }
    }

    /// Earlier conversations of a scope, newest first.
    func chatHistory(_ key: String) -> [ChatSummary] { archive?.list(scope: key) ?? [] }

    /// Shows an earlier conversation of the scope. Not while a turn streams into the current one.
    func openChat(_ key: String, id: UUID) {
        let conv = conversation(key)
        guard !conv.running, conv.id != id, let a = archive?.load(scope: key, id: id) else { return }
        conv.restore(a)
    }

    func deleteChat(_ key: String, id: UUID) {
        let conv = conversation(key)
        guard !(conv.running && conv.id == id) else { return }
        do { try archive?.delete(scope: key, id: id) } catch { toasts.error("Could not delete the conversation", error) }
        if conv.id == id { conv.reset() }
    }

    private var who: String {
        if let p = profile, !p.name.isEmpty {
            let w = [p.name, p.affiliation ?? "", p.unit ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
            let lang = (p.language ?? "").isEmpty ? "" : "; default language \(p.language!)"
            return "Presenter: \(w)\(lang). The full profile is studio.json at the repo root; read it before writing a title or closing slide."
        }
        return "No presenter profile yet; ask for names and contact lines instead of inventing them."
    }
    private var sourcesNote: String {
        sourceCount > 0 ? "\(sourceCount) source file(s) attached: call list_sources, search them with rag_search, and cite them." : "No source files attached yet."
    }

    var lectureScope: ChatScope {
        let title = Labels.courseTitle(course, meta)
        let w = word
        return ChatScope(
            key: course,
            label: talk ? "Talk: \(title)" : "Course: \(title)",
            tags: scopeTags(course: course == "(root)" ? "" : course, unit: nil),
            context: "\(talk ? "Talk" : "Course") open in the app: \(course). No \(w) is open. \(who) \(sourcesNote)",
            starters: talk ? Starters.talk(filePath) : Starters.course(w),
            hint: sourceCount == 0
                ? (talk ? "No sources attached yet. Add the material the talk should draw on, then ask for an outline." : "No sources attached yet. Add the readings first, so the \(w) decks can cite them.")
                : (talk ? "Plan and write the talk from your sources. One click fills the box; edit before you send." : "Plan the course, or open a \(w) for its deck. One click fills the box; edit before you send."),
            emptyActions: sourceCount == 0 ? [EmptyAction(label: "Add sources", icon: "book", dialog: .sources)] : []
        )
    }

    var weekScope: ChatScope? {
        guard let u = unit else { return nil }
        let w = word
        var actions: [EmptyAction] = []
        if sourceCount == 0 { actions.append(EmptyAction(label: "Add sources", icon: "book", dialog: .sources)) }
        if !isDeck && !talk { actions.append(EmptyAction(label: "New \(w)", icon: "plus", dialog: .week)) }
        return ChatScope(
            key: "\(course)/\(u)",
            label: talk ? "This talk" : Labels.unitLabel(u),
            tags: scopeTags(course: course == "(root)" ? "" : course, unit: u),
            context: "\(talk ? "Talk" : "Course"): \(course). \(talk ? "Folder" : "\(w.capFirst) folder"): \(u.isEmpty ? "(course root)" : u). File open in the app: \(filePath.isEmpty ? "none" : filePath). \(who) \(sourcesNote)",
            starters: talk ? Starters.talk(filePath) : Starters.unit(w, filePath, isDeck),
            hint: sourceCount == 0
                ? "No sources for this \(talk ? "talk" : w) yet. Add them first; every starter below leans on them."
                : (isDeck ? "Work on the open deck, from outline to speaker notes. One click fills the box; edit before you send." : "Ask for the \(w) deck, an edit, a check, or notes. One click fills the box; edit before you send."),
            emptyActions: actions
        )
    }

    /// Sends, or queues while a turn runs: queued messages go out one by one when a turn completes.
    func sendMessage(scope: ChatScope, text: String, attachments: [PendingAttachment] = []) async {
        let conv = conversation(scope.key)
        let t = text.trimmed
        guard !t.isEmpty || !attachments.isEmpty else { return }
        guard AppSettings.hasOberik else {
            toasts.error("Oberik is not configured", "Open Settings and add the project id and key.")
            return
        }
        if conv.running { conv.queued.append(QueuedMessage(text: t, attachments: attachments)); return }
        var payloads: [[String: Any]] = []
        do { payloads = try attachments.map { try $0.payload() } } catch {
            toasts.error("Could not attach the file", error)
            return
        }
        conv.running = true
        conv.turnStarted = Date()
        var userMsg = ChatMessage(role: .user, content: t.isEmpty ? "(attached \(attachments.count) file\(attachments.count == 1 ? "" : "s"))" : t)
        userMsg.attachments = attachments.map { ChatAttachment(id: nil, kind: $0.isImage ? "image" : "file", url: $0.url.absoluteString, name: $0.name, mime_type: $0.mime) }
        conv.messages.append(userMsg)
        conv.messages.append(ChatMessage(role: .assistant, content: ""))
        saveConversation(conv)
        let id = UUID().uuidString
        conv.turnId = id
        do {
            try await agent.send(id: id, message: t.isEmpty ? "See the attached file(s)." : t, context: scope.context, sessionId: conv.sessionId, model: model, tags: scope.tags, attachments: payloads)
        } catch {
            conv.patchLast(now: true) { $0.error = error.localizedDescription }
            conv.running = false
            conv.turnId = nil
            conv.turnStarted = nil
            toasts.error("The assistant stopped", error)
        }
    }

    /// A message into the running turn: the agent reads it at its next step, as the user speaking. It
    /// shows in the transcript where it landed, before the reply. When the turn ended first, the message
    /// goes out as the next one. Returns whether it was read into the turn.
    @discardableResult
    func steer(scope: ChatScope, text: String) async -> Bool {
        let conv = conversation(scope.key)
        let t = text.trimmed
        guard !t.isEmpty else { return false }
        guard conv.running, let id = conv.turnId else { await sendMessage(scope: scope, text: t); return false }
        guard conv.pendingSteer == nil else { toasts.show(.info, "One steering note at a time", "The earlier note is still waiting for the assistant's next step."); return false }
        conv.pendingSteer = t
        let accepted = await agent.steer(id: id, message: t)
        conv.pendingSteer = nil
        if accepted {
            var m = ChatMessage(role: .user, content: t)
            m.steering = true
            conv.flushPatches()
            conv.messages.insert(m, at: max(0, conv.messages.count - 1))
            saveConversation(conv)
            return true
        }
        // The turn ended before a step could take it: it goes out as the next message.
        toasts.show(.info, "The assistant finished before reading your note", "It goes out as the next message.")
        await sendMessage(scope: scope, text: t)
        return false
    }

    func removeQueued(_ key: String, id: UUID) { conversation(key).queued.removeAll { $0.id == id } }

    /// The scope a conversation key belongs to, when it is one of the scopes open now.
    func scope(for key: String) -> ChatScope? {
        if lectureScope.key == key { return lectureScope }
        if let w = weekScope, w.key == key { return w }
        return nil
    }

    /// Sends the first queued message of a conversation that is free (the scope must still be open).
    func sendNextQueued(_ key: String) {
        let conv = conversation(key)
        guard !conv.running, let next = conv.queued.first, let scope = scope(for: key) else { return }
        conv.queued.removeFirst()
        Task { await sendMessage(scope: scope, text: next.text, attachments: next.attachments) }
    }

    func cancelTurn(_ key: String) {
        guard let id = conversation(key).turnId else { return }
        Task { await agent.cancel(id: id) }
    }

    /// `New`: the current conversation stays in the archive; the next message starts another session.
    func resetConversation(_ key: String) {
        cancelTurn(key)
        let conv = conversation(key)
        saveConversation(conv)
        conv.reset()
    }

    func setModel(_ m: String) {
        model = m
        AppSettings.model = m
    }

    private func handleChat(id: String, event: String, _ d: [String: Any]) {
        guard let conv = conversations.values.first(where: { $0.turnId == id }) else { return }
        switch event {
        case "token":
            // The page posts the whole text so far, at most a few times a second (agent.ts coalesces
            // tokens); the store queues the patch as well, so the transcript is safe from a chatty page.
            if let full = d["full"] as? String { conv.patchLast { $0.content = full } }
        case "reasoning":
            let n = d["chars"] as? Int ?? 0
            conv.patchLast { m in if m.content.isEmpty { m.events.removeAll { $0.hasPrefix("thinking") }; m.events.append("thinking (\(n) chars)") } }
        case "toolStart":
            conv.patchLast { $0.events.append("▶ \(d["name"] as? String ?? "") \(d["summary"] as? String ?? "")") }
        case "toolEnd":
            conv.patchLast { $0.events.append("✓ \(d["name"] as? String ?? "")") }
        case "toolCalls":
            let calls = d["calls"] as? [[String: Any]] ?? []
            conv.patchLast { m in for c in calls { m.events.append("▶ \(c["name"] as? String ?? "") \(c["summary"] as? String ?? "")") } }
        case "attachments":
            if let a = decodeBridge([ChatAttachment].self, d["attachments"]) { conv.patchLast { $0.attachments = a } }
        case "citations":
            if let c = decodeBridge([ChatCitation].self, d["citations"]) { conv.patchLast { $0.citations = c } }
        case "todos":
            conv.flushPatches()
            conv.todos = decodeBridge([ChatTodo].self, d["todos"]) ?? []
        case "command":
            let cmd = d["command"] as? String ?? ""
            let delta = d["delta"] as? String ?? ""
            conv.patchLast { m in
                let key = "$ \(cmd)"
                if let i = m.events.firstIndex(where: { $0.hasPrefix(key) }) { m.events[i] = String((m.events[i] + delta).prefix(2000)) } else { m.events.append(String("\(key)\n\(delta)".prefix(2000))) }
            }
        case "approval":
            conv.flushPatches()
            conv.approval = decodeBridge(ApprovalRequest.self, d["request"])
        case "question":
            conv.flushPatches()
            conv.question = decodeBridge(PendingQuestions.self, d["pending"])
        case "done":
            let r = d["result"] as? [String: Any] ?? [:]
            if let sid = r["session_id"] as? String, !sid.isEmpty { conv.sessionId = sid }
            let content = r["content"] as? String ?? ""
            let atts = decodeBridge([ChatAttachment].self, r["attachments"]) ?? []
            let cits = decodeBridge([ChatCitation].self, r["citations"]) ?? []
            let modelName = r["model"] as? String
            let steered = r["steered"] as? [String] ?? []
            conv.patchLast(now: true) { m in
                if !content.isEmpty { m.content = content }
                if !atts.isEmpty { m.attachments = atts }
                if !cits.isEmpty { m.citations = cits }
                for s in steered { m.events.append("↪ read while working: \(s)") }
                if let modelName, !modelName.isEmpty { m.events.append("model \(modelName)") }
            }
            finishTurn(conv, completed: true)
        case "error":
            let msg = d["message"] as? String ?? "stream failed"
            conv.patchLast(now: true) { $0.error = msg }
            toasts.error("The assistant stopped", msg)
            finishTurn(conv, completed: false)
        default: break
        }
    }

    /// Ends the turn. After a completed one the next queued message goes out; after a stop or an
    /// error the queue waits for the user.
    private func finishTurn(_ conv: Conversation, completed: Bool) {
        conv.running = false
        conv.turnId = nil
        conv.turnStarted = nil
        conv.approval = nil
        conv.question = nil
        saveConversation(conv)
        if completed { sendNextQueued(conv.key) }
    }

    func answerApproval(_ conv: Conversation, approved: Bool) {
        guard let a = conv.approval else { return }
        conv.approval = nil
        Task { await agent.resolveApproval(a.tool_call_id, approved: approved) }
    }

    func answerQuestion(_ conv: Conversation, answer: [String: Any]) {
        guard let q = conv.question else { return }
        conv.question = nil
        var a = answer
        a["tool_call_id"] = q.tool_call_id
        Task { await agent.answerQuestion(q.tool_call_id, answer: a) }
    }

    /// Save an attachment of the chat into `<dir>/assets/`.
    func saveAttachment(url: String, dir: String, name: String) async throws -> Assets.Saved {
        guard let fs = repo else { throw AgentError("no repository open") }
        let s = try await Assets.save(fs: fs, weekDir: dir, filename: name, source: url)
        onFileChanged(s.path)
        return s
    }

    var currentDir: String { filePath.isEmpty ? "" : deckDir(filePath) }
}

struct GettingStartedState: Equatable {
    var profile: Bool
    var course: Bool
    var sources: Bool
    var assistant: Bool
}

/// One row of the sources sheet: a file on disk, a document on Oberik, or both.
struct SourceRow: Identifiable, Equatable {
    var key: String
    var name: String
    var path: String?
    var scope: SourceScope
    var doc: OberikDocument?
    var size: Int?
    var id: String { key }
    var pending: Bool { doc == nil }
}

/// The starter prompts of an empty conversation.
enum Starters {
    static func course(_ word: String) -> [Starter] {
        [
            Starter(label: "Plan the \(word)s from the sources", prompt: "Call list_sources, read the syllabus and the course AGENTS.md, and search the sources. Propose a \(word)-by-\(word) plan: topic, one learning outcome, which source chapters or sections it draws on, and one practice idea per \(word). Wait for my approval before creating anything."),
            Starter(label: "Summarize the sources", prompt: "Call list_sources, then summarize each source in 5 bullets: its main claims, the examples worth using in class, and what to skip. Cite page or section numbers."),
            Starter(label: "Draft the syllabus", prompt: "Read syllabus.md and the sources. Fill in the objectives, the learning outcomes, the \(word)ly subjects with readings, and the evaluation table. Keep the existing headings. Show me the \(word) table before you write the file."),
            Starter(label: "Course policies slide text", prompt: "Read studio.json at the repo root and the course AGENTS.md. Draft the course-policy slides for the first deck: exams, attendance, AI use, pacing, contact. Plain slides, one topic each; show them in the chat first."),
        ]
    }

    static func unit(_ word: String, _ filePath: String, _ isDeck: Bool) -> [Starter] {
        let deck = isDeck && !filePath.isEmpty ? "the open deck (\(filePath))" : "the \(word) deck"
        return [
            Starter(label: "Outline from the sources", prompt: "Call list_sources and read the syllabus row for this \(word) and the previous \(word)'s deck. Search the sources. Propose an outline for \(deck): blocks, the slides of each block with a working title, where the practice and question slides go, and which source each block draws on. Wait for my approval before writing any slide."),
            Starter(label: "Write the deck from the outline", prompt: "Write \(deck) from the approved outline, in sections of 10-15 slides. Ground every content slide in the sources and cite them in the slide footer. Preview and run QA after each section and fix what it reports."),
            Starter(label: "Speaker notes", prompt: "Add speaker notes to every content slide of \(deck) as an HTML comment at the end of the slide: 2-4 sentences on what to say, one question to ask the room, and the transition to the next slide. Do not change the slide content. Use replace_in_file, one slide at a time."),
            Starter(label: "Practice questions", prompt: "Write retrieval-practice questions for \(deck), one per block, grounded in the sources: a question slide followed by an answer slide, inserted at the end of each block. Show me the questions before you edit the deck."),
            Starter(label: "Tighten the slides", prompt: "Run qa_deck on \(deck), then fix every overflow and density problem by splitting slides, never by deleting content. Report the slide numbers you changed."),
            Starter(label: "\(word.capFirst) guide", prompt: "Write the instructor guide for \(deck): 20-minute blocks, the student output of each block, facilitation notes, a minimum viable path for a class that runs late, and one extension."),
        ]
    }

    static func talk(_ filePath: String) -> [Starter] {
        let deck = filePath.isEmpty ? "the talk deck" : "the open deck (\(filePath))"
        return [
            Starter(label: "Outline the talk from the sources", prompt: "Call list_sources and search the sources. Propose an outline for \(deck): the one message the audience should leave with, 4-6 sections with slide titles, where a story, demo, or example goes, and which source backs each section. Ask me for the talk length if it is not in the deck. Wait for my approval before writing slides."),
            Starter(label: "Write the talk from the outline", prompt: "Write \(deck) from the approved outline, in sections. One idea per slide, big claims with the source in the footer, a story or example every few slides. Preview and run QA after each section."),
            Starter(label: "Speaker notes", prompt: "Add speaker notes to every slide of \(deck) as an HTML comment at the end of the slide: what to say in 2-4 sentences, the transition to the next slide, and a timing mark. Do not change the slide content. Use replace_in_file, one slide at a time."),
            Starter(label: "Rehearsal timing", prompt: "Estimate the speaking time of each slide of \(deck) (about 120 words a minute, plus a minute for a diagram or a demo). List the slides that run long and suggest what to cut for a version that is a third shorter. Do not edit the deck."),
            Starter(label: "Audience Q&A prep", prompt: "From the sources and \(deck), write the 8 questions the audience is most likely to ask, with a two-sentence answer each and the source to point at. Save it as qa-prep.md next to the deck."),
            Starter(label: "Summarize the sources", prompt: "Call list_sources, then summarize each source in 5 bullets: the claims worth quoting, the numbers and examples, and what to leave out. Cite page or section numbers."),
        ]
    }
}
