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

    var body: some View {
        TabView {
            Form { librarySection }.formStyle(.grouped).tabItem { Label("Library", systemImage: "folder") }
            Form { oberikSection }.formStyle(.grouped).tabItem { Label("Agent", systemImage: "sparkles") }
        }
        .frame(width: 540, height: 400)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
