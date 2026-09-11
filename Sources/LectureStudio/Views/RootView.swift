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
    @State private var planText = AppSettings.lecturePlan
    @State private var breakText = String(AppSettings.breakMinutes)

    var body: some View {
        TabView {
            Form { librarySection }.formStyle(.grouped).tabItem { Label("Library", systemImage: "folder") }
            Form { teachingSection }.formStyle(.grouped).tabItem { Label("Teaching", systemImage: "timer") }
            Form { oberikSection }.formStyle(.grouped).tabItem { Label("Agent", systemImage: "sparkles") }
        }
        .frame(width: 540, height: 500)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .onAppear {
            // The defaults live on the store, so a rhythm picked in presenter mode shows up here too.
            planText = store.lecturePlan.text
            breakText = String(store.lectureBreakMinutes)
        }
    }

    /// The lecture clock's system-wide defaults: the rhythm every lecture starts with, and what a break the
    /// lecturer starts by hand lasts.
    @ViewBuilder var teachingSection: some View {
        Section {
            HStack {
                TextField("20 5 20 15", text: $planText)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()      // the section is the label; the string here is the empty field's format
                    .onSubmit { applyPlan() }
                Menu("Presets") {
                    ForEach(LecturePlan.presets) { p in
                        let plan = LecturePlan(p.text)
                        Button("\(plan.compact) — \(plan.roundMinutes) min round") {
                            planText = plan.text
                            store.setLecturePlan(plan)
                        }
                    }
                }
                .fixedSize()
                Button("Apply") { applyPlan() }.disabled(planText.trimmed == store.lecturePlan.text)
            }
            Text(LecturePlan(planText).summary).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Lecture rhythm")
        } footer: {
            Text("Teaching and break minutes, in the order you teach them. Presenter mode counts each block down and, with auto break on, hands the room over to the break after it. One round is \(LecturePlan(planText).roundMinutes) minutes and then it starts again, so a three-hour slot keeps the rhythm. Presenter mode can run another rhythm for a single lecture without changing this.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Hand-started break") {
                HStack(spacing: 4) {
                    TextField("10", text: $breakText).frame(width: 56).multilineTextAlignment(.trailing)
                        .onChange(of: breakText) { _, v in if let n = Int(v.trimmed) { store.setLectureBreakMinutes(n) } }
                    Text("min")
                }
            }
            Toggle("Auto break", isOn: Binding(get: { store.autoBreak }, set: { store.setAutoBreak($0) }))
        } header: {
            Text("Breaks")
        } footer: {
            Text("A break the rhythm calls lasts as long as the rhythm says; this is the length of one you start yourself with the Break button. With auto break off the block still counts down, and you decide when the break comes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func applyPlan() {
        store.setLecturePlan(LecturePlan(planText))
        planText = store.lecturePlan.text
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
