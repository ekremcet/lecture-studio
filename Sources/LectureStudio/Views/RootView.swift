import SwiftUI
import AppKit
import StudioCore

struct RootView: View {
    @Environment(StudioStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack {
            switch store.stage {
            case .noRepo: RepoPickerView()
            case .lectures: LecturePickerView()
            case .weeks: WeekPickerView()
            case .work: WorkspaceView()
            }
            ToastOverlay(center: store.toasts)
            // The agent page stays in the window (1 pt, invisible) so WebKit never throttles it as a background page.
            WebViewHost(webView: store.agent.webView).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .sheet(item: $store.dialog) { d in
            switch d {
            case .profile: ProfileSheet()
            case .sources: SourcesSheet()
            case .lecture: NewCourseSheet()
            case .talk: NewTalkSheet()
            case .week: NewUnitSheet()
            case .file: NewFileSheet()
            case .editLecture: EditLectureSheet()
            case .importCourse: ImportCourseSheet()
            case .newTerm: NewTermSheet()
            case .compare: CompareSheet()
            case .remove: RemoveCourseSheet()
            case .marpHelp: MarpHelpSheet()
            case .export: ExportSheet()
            case .publish: PublishSheet()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Lecture Studio")
    }
}

/// First launch: where is the material? Any folder works; git is optional.
struct RepoPickerView: View {
    @Environment(StudioStore.self) private var store

    var body: some View {
        EmptyBlock(icon: "folder.badge.gearshape", title: "Where is your material?", description: "A folder with one subfolder per course or talk. Lecture Studio reads and writes decks there, and the agent works only inside it. Git is optional: a plain folder is fine, and a repository gets a commit bar.") {
            HStack {
                Button("Create a new library…") { create() }.keyboardShortcut(.defaultAction)
                Button("Open a folder…") { choose() }
                SettingsLink { Text("Settings") }
            }
        }
    }

    func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Open"
        p.message = "Choose the folder that holds your courses and talks"
        if p.runModal() == .OK, let u = p.url { store.openRepo(u) }
    }

    /// An empty folder, no git. The getting-started checklist takes over from there.
    func create() {
        let p = NSSavePanel()
        p.canCreateDirectories = true
        p.prompt = "Create"
        p.message = "Name the folder for your courses and talks"
        p.nameFieldStringValue = "Lecture Studio"
        p.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            store.openRepo(u)
        } catch { store.toasts.error("Could not create the folder", error) }
    }
}

struct SettingsView: View {
    @Environment(StudioStore.self) private var store
    @State private var repo = AppSettings.repoPath ?? ""
    @State private var projectId = AppSettings.projectId
    @State private var projectKey = AppSettings.projectKey
    @State private var subject = AppSettings.subject
    @State private var status = ""
    @State private var testing = false
    @State private var shortcutMessage = ""
    @State private var formats: [LectureFormat] = []
    @State private var breakText = String(AppSettings.breakMinutes)
    @State private var marpPath = AppSettings.marpPath
    @State private var platformToken = AppSettings.platformToken
    @State private var platformOrigin = AppSettings.platformOrigin
    @State private var platformStatus = ""
    @State private var platformTesting = false
    @State private var browserPath = AppSettings.browserPath

    var body: some View {
        TabView {
            Form { librarySection }.formStyle(.grouped).tabItem { Label("Library", systemImage: "folder") }
            Form { teachingSection }.formStyle(.grouped).tabItem { Label("Teaching", systemImage: "timer") }
            Form { oberikSection }.formStyle(.grouped).tabItem { Label("Agent", systemImage: "sparkles") }
            Form { exportSection }.formStyle(.grouped).tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            Form { publishSection }.formStyle(.grouped).tabItem { Label("Publish", systemImage: "arrow.up.circle") }
            Form { shortcutsSection }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 500)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .onAppear {
            // The defaults live on the store; the pane edits a copy and hands every change back.
            formats = store.lectureFormats
            breakText = String(store.lectureBreakMinutes)
        }
    }

    /// The lecture clock's system-wide defaults: the formats, the one every lecture starts with, and what a
    /// break of the lecturer's own lasts.
    @ViewBuilder var teachingSection: some View {
        Section {
            VStack(spacing: 0) {
                ForEach($formats) { $f in
                    FormatRow(format: $f, canRemove: formats.count > 1) { formats.removeAll { $0.id == f.id } }
                    if f.id != formats.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .onChange(of: formats) { _, list in store.setLectureFormats(list) }
            Button { formats.append(LectureFormat(name: "New format", icon: "", rhythm: LecturePlan.defaultText)) } label: { Label("Add format", systemImage: "plus") }
            Picker("Start lectures with", selection: Binding(get: { store.lectureFormatId }, set: { store.setLectureFormat($0) })) {
                ForEach(store.lectureFormats) { f in FormatLabel(format: f).tag(f.id) }
            }
        } header: {
            Text("Lecture formats")
        } footer: {
            Text("A format is a name, a symbol and its rhythm: teaching and break minutes in the order you teach them. Presenter mode counts each block down and, with auto break on, hands the room over to the break after it; after the last break the rhythm starts again, so a three-hour slot keeps it. The presenter's strip names the format and can switch to another one for a single lecture without changing the default.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Hand-started break") {
                HStack(spacing: 4) {
                    TextField("10", text: $breakText).labelsHidden().frame(width: 56).multilineTextAlignment(.trailing)
                        .onChange(of: breakText) { _, v in if let n = Int(v.trimmed) { store.setLectureBreakMinutes(n) } }
                    Text("min")
                }
            }
            Toggle("Auto break", isOn: Binding(get: { store.autoBreak }, set: { store.setAutoBreak($0) }))
        } header: {
            Text("Breaks")
        } footer: {
            Text("A break the rhythm calls lasts as long as the rhythm says; this is the length of one you start yourself with \(store.shortcut(for: .toggleBreak)?.display ?? "the Break button"). With auto break off the block still counts down, and you decide when the break comes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var librarySection: some View {
            Section("Library folder") {
                HStack {
                    TextField("Path", text: $repo).font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true
                        p.canChooseFiles = false
                        p.canCreateDirectories = true
                        if p.runModal() == .OK, let u = p.url { repo = u.path }
                    }
                }
                HStack {
                    Button("Open this folder") { store.openRepo(URL(fileURLWithPath: repo)) }.disabled(repo.isEmpty)
                    if store.repo != nil && !store.gitAvailable {
                        Button("Track changes with git") { Task { await store.initGit() } }
                    }
                }
                Text(store.gitAvailable ? "This folder is a git repository: the commit bar, pull and push are on." : "Git is optional. Without it the app works on the folder directly; turn it on to get the commit bar.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Hidden folders") {
                let hidden = store.profile?.exclude ?? []
                if hidden.isEmpty {
                    Text("Nothing hidden. Use \"Hide from the studio\" on a folder that is neither a course nor a talk, such as scripts or tooling.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(hidden, id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "folder").font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Show again") { store.setExcluded(name, false) }.controlSize(.small)
                        }
                    }
                }
            }
    }

    @ViewBuilder var shortcutsSection: some View {
            Section {
                ForEach(ShortcutAction.allCases) { a in
                    LabeledContent(a.title) { ShortcutRecorder(action: a, message: $shortcutMessage) }
                }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Click a shortcut and type the new one. Escape keeps the old one, Delete removes it. Menus follow the change at once.").font(.caption).foregroundStyle(.secondary)
            }
            if !shortcutMessage.isEmpty {
                Section { Text(shortcutMessage).font(.callout).foregroundStyle(.orange) }
            }
            Section {
                Button("Reset all to defaults") { store.resetShortcuts(); shortcutMessage = "" }
                    .disabled(store.shortcuts.overrides.isEmpty)
            }
    }

    /// Export runs marp-cli; the app finds it (shell PATH, Homebrew, npm, npx) unless a path is given here.
    @ViewBuilder var exportSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                switch store.exporter.status {
                case .unknown, .probing:
                    ProgressView().controlSize(.small)
                    Text("Looking for marp-cli…").foregroundStyle(.secondary)
                case .ready(let t):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.label), from \(t.origin)")
                        Text(t.command.joined(separator: " ")).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                case .missing(let e):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.message)
                        if let h = e.hint { Text(h).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                Spacer()
                Button("Look again") { store.exporter.settingsChanged() }.controlSize(.small)
            }
            HStack {
                TextField("marp-cli path (optional)", text: $marpPath).font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.canChooseFiles = true
                    p.canChooseDirectories = true
                    p.showsHiddenFiles = true
                    p.message = "The marp executable, or the folder that holds it"
                    if p.runModal() == .OK, let u = p.url { marpPath = u.path }
                }
            }
            .onChange(of: marpPath) { _, v in AppSettings.marpPath = v.trimmed; store.exporter.settingsChanged() }
        } header: {
            Text("marp-cli")
        } footer: {
            Text("Export hands the deck to marp-cli, the command-line Marp. The app looks in your shell's PATH, Homebrew, npm's global folder, node version managers and the npx cache, and falls back to `npx @marp-team/marp-cli`; a path here comes first. Install it with `brew install marp-cli` or `npm install -g @marp-team/marp-cli`.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            let browsers = Exporter.installedBrowsers()
            Text(browsers.isEmpty ? "No Chrome, Edge, Chromium or Firefox in Applications." : "In Applications: \(browsers.joined(separator: ", ")).").foregroundStyle(.secondary)
            HStack {
                TextField("Browser executable (optional)", text: $browserPath).font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.canChooseFiles = true
                    p.canChooseDirectories = false
                    p.showsHiddenFiles = true
                    p.treatsFilePackagesAsDirectories = true
                    p.message = "The browser's executable, e.g. Google Chrome.app/Contents/MacOS/Google Chrome"
                    if p.runModal() == .OK, let u = p.url { browserPath = u.path }
                }
            }
            .onChange(of: browserPath) { _, v in AppSettings.browserPath = v.trimmed }
            Text(Exporter.libreOfficeInstalled() ? "LibreOffice is installed: the experimental editable PowerPoint is available." : "Editable PowerPoint (experimental) also needs LibreOffice, which is not installed. The plain PowerPoint, one image per slide, needs only the browser.").font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Browser")
        } footer: {
            Text("PDF and PowerPoint are printed by a browser: Google Chrome, Microsoft Edge, Chromium or Firefox. marp-cli finds them in Applications on its own; name one here only when it lives elsewhere (passed as --browser-path).").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The lecture.studio account this Mac publishes to: connected through the website, or a pasted token.
    @ViewBuilder var publishSection: some View {
        Section("Your page on lecture.studio") {
            Text("Publishing sends a course's decks, PDFs and syllabus to your page at lecture.studio/@you, where students get each week's materials on lecture day. Connect once: the website signs you in and hands the app a token.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { store.connectPlatform() } label: { Label(store.platformHandle == nil ? "Connect lecture.studio" : "Connect again", systemImage: "link") }.buttonStyle(.borderedProminent)
                if let h = store.platformHandle { Label("Connected as @\(h)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else if !platformToken.trimmed.isEmpty { Label("A token is set", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                Button { testPlatform() } label: { BusyLabel(busy: platformTesting, idle: "Test", working: "Testing…") }.disabled(platformTesting || AppSettings.platformToken.trimmed.isEmpty)
            }
            if !platformStatus.isEmpty { Text(platformStatus).font(.caption).foregroundStyle(.secondary) }
        }
        Section("Token") {
            SecureField("Paste a token from lecture.studio/settings instead", text: $platformToken)
                .onChange(of: platformToken) { _, v in
                    guard v.trimmed != AppSettings.platformToken else { return }
                    // Another token may be another account: the handle is learned again from Test or the next publish.
                    AppSettings.platformToken = v.trimmed; platformStatus = ""
                    AppSettings.platformHandle = ""; store.platformHandle = nil
                    store.refreshPublishState()
                }
            Text("A token can do everything your account can. Revoke it on the website under Settings › Mac app if a Mac is lost.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            TextField("https://lecture.studio", text: $platformOrigin).font(.system(.body, design: .monospaced))
                .onChange(of: platformOrigin) { _, v in AppSettings.platformOrigin = v.trimmed.isEmpty ? "https://lecture.studio" : v.trimmed }
        } header: { Text("Server") } footer: {
            Text("Leave this alone unless you run the platform yourself.").font(.caption).foregroundStyle(.secondary)
        }
    }

    func testPlatform() {
        guard let origin = URL(string: platformOrigin.trimmed) else { platformStatus = "The server address is not a URL."; return }
        platformTesting = true
        let client = PlatformClient(origin: origin, token: AppSettings.platformToken.trimmed)
        Task {
            do {
                let me = try await client.me()
                AppSettings.platformHandle = me.handle
                store.platformHandle = me.handle
                store.refreshPublishState()
                platformToken = AppSettings.platformToken
                platformStatus = "Signed in as @\(me.handle)\(me.courses.isEmpty ? "" : ", \(me.courses.count) course\(me.courses.count == 1 ? "" : "s") on the page")."
            } catch { platformStatus = error.localizedDescription }
            platformTesting = false
        }
    }

    @ViewBuilder var oberikSection: some View {
            Section("The assistant runs on Oberik") {
                Text("1. Create an account and a project at oberik.com; add a model provider, pick a default and an embedding model, allow the capabilities.\n2. Create a project key under API keys and copy the project id from Connect the SDK.\n3. Paste them below and press Test connection.\n4. Publish the skill pack once so the assistant knows the deck conventions: in the checkout, `npm run skills:publish` (it also allows this app's origin).").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button { NSWorkspace.shared.open(oberikGuideURL) } label: { Label("Step-by-step guide", systemImage: "book") }
                    Button { NSWorkspace.shared.open(oberikURL) } label: { Label("Open oberik.com", systemImage: "safari") }
                }
            }
            Section("Oberik project") {
                TextField("Project id", text: $projectId).font(.system(.body, design: .monospaced))
                SecureField("Project key", text: $projectKey)
                TextField("Subject", text: $subject)
                Text("Private documents are visible only to the subject that indexed them. Changing the subject hides the sources indexed so far.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save") { save() }
                    Button("Import from .env") {
                        if AppSettings.importDotEnv() {
                            projectId = AppSettings.projectId
                            projectKey = AppSettings.projectKey
                            subject = AppSettings.subject
                            store.oberikSettingsChanged()
                            status = "Imported from the project's .env into the Keychain."
                        } else { status = "No .env with OBERIK_PROJECT_ID next to the app." }
                    }
                    Button { test() } label: { BusyLabel(busy: testing, idle: "Test connection", working: "Testing…") }.disabled(testing || projectId.isEmpty || projectKey.isEmpty)
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
    }

    func save() {
        AppSettings.projectId = projectId.trimmed
        AppSettings.projectKey = projectKey.trimmed
        AppSettings.subject = subject.trimmed.isEmpty ? "presenter" : subject.trimmed
        if !repo.isEmpty { AppSettings.repoPath = repo }
        store.oberikSettingsChanged()
        status = "Saved. The key is in the Keychain."
    }

    func test() {
        save()
        testing = true
        Task {
            do {
                let t = try await OberikControl(projectId: projectId.trimmed, projectKey: projectKey.trimmed).mint(subject: subject)
                let pong = try await store.agent.ping()
                status = "Token minted (\(t.capabilities.count) capabilities). Agent replied: \(pong.prefix(60))"
            } catch { status = "Failed: \(error.localizedDescription)" }
            testing = false
        }
    }
}

/// One lecture format in Settings › Teaching: its symbol, its name, its rhythm and, under the name, how the
/// rhythm reads.
struct FormatRow: View {
    @Binding var format: LectureFormat
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Menu {
                Button { format.icon = "" } label: { Label("None", systemImage: "circle.dashed") }
                Divider()
                ForEach(LectureFormat.icons, id: \.symbol) { i in
                    Button { format.icon = i.symbol } label: { Label(i.name, systemImage: i.symbol) }
                }
            } label: {
                Image(systemName: format.icon.isEmpty ? "circle.dashed" : format.icon)
                    .foregroundStyle(format.icon.isEmpty ? .tertiary : .primary)
                    .frame(width: 18)
            }
            .menuIndicator(.hidden)
            .frame(width: 44)
            .help("The symbol the presenter's strip shows next to the name")
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: Binding(get: { format.name }, set: { format.name = String($0.prefix(LectureFormat.nameLimit)) }))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .font(.body.weight(.medium))
                Text("\(format.plan.compact) · \(format.plan.roundMinutes) min round")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            TextField("20 5 20 15", text: $format.rhythm)
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
                .frame(width: 184)
                .help("Teaching and break minutes, in the order you teach them: 20 5 20 15 is twenty on, five off, twenty on, fifteen off")
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(!canRemove)
                .help(canRemove ? "Remove this format" : "The last format stays")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}
