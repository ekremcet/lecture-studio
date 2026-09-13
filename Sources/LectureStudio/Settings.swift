import Foundation
import Security
import StudioCore

/// Where the app keeps what is not in the repo: the repo location, and the Oberik project credentials.
/// The project key lives in the Keychain; everything else in UserDefaults.
enum AppSettings {
    static let defaults = UserDefaults.standard
    static let service = "com.akademi.lecture-studio"

    static var repoPath: String? {
        get { defaults.string(forKey: "repoPath") }
        set { defaults.set(newValue, forKey: "repoPath") }
    }
    static var projectId: String {
        get { defaults.string(forKey: "oberikProjectId") ?? "" }
        set { defaults.set(newValue, forKey: "oberikProjectId") }
    }
    /// Private documents are visible only to the subject that uploaded them; changing this hides the existing index.
    static var subject: String {
        get { defaults.string(forKey: "oberikSubject") ?? "presenter" }
        set { defaults.set(newValue, forKey: "oberikSubject") }
    }
    static var projectKey: String {
        get { Keychain.read(service: service, account: "oberikProjectKey") ?? "" }
        set { Keychain.write(service: service, account: "oberikProjectKey", value: newValue) }
    }
    static var model: String {
        get { defaults.string(forKey: "chatModel") ?? "" }
        set { defaults.set(newValue, forKey: "chatModel") }
    }
    static var showNotes: Bool {
        get { defaults.object(forKey: "showNotes") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showNotes") }
    }
    /// Presenter mode's system-wide defaults: the lecture formats (a name, a symbol and the teaching and
    /// break minutes in order) and the one every lecture starts with, the break a hand-started Break lasts,
    /// and whether a block that runs out hands the room over by itself.
    static var lectureFormats: [LectureFormat]? {
        get { defaults.data(forKey: "lectureFormats").flatMap { try? JSONDecoder().decode([LectureFormat].self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lectureFormats") }
    }
    static var lectureFormatId: UUID? {
        get { defaults.string(forKey: "lectureFormat").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "lectureFormat") }
    }
    /// The single rhythm of versions before the formats list; read once to seed it.
    static var legacyLecturePlan: String? { defaults.string(forKey: "lecturePlan") }
    static var breakMinutes: Int {
        get { defaults.object(forKey: "breakMinutes") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "breakMinutes") }
    }
    static var autoBreak: Bool {
        get { defaults.object(forKey: "autoBreak") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoBreak") }
    }
    static var panelOrder: [String] {
        get { defaults.stringArray(forKey: "panelOrder") ?? [] }
        set { defaults.set(newValue, forKey: "panelOrder") }
    }
    static var panelFractions: [String: Double] {
        get { defaults.dictionary(forKey: "panelFractions") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "panelFractions") }
    }
    static var hiddenPanels: [String] {
        get { defaults.stringArray(forKey: "hiddenPanels") ?? [] }
        set { defaults.set(newValue, forKey: "hiddenPanels") }
    }
    static var courseSort: String {
        get { defaults.string(forKey: "courseSort") ?? "term" }
        set { defaults.set(newValue, forKey: "courseSort") }
    }
    static var courseOrder: [String] {
        get { defaults.stringArray(forKey: "courseOrder") ?? [] }
        set { defaults.set(newValue, forKey: "courseOrder") }
    }
    /// The user's keyboard shortcuts: action → encoded shortcut, "" for none. Absent means the default.
    static var shortcuts: [String: String] {
        get { defaults.dictionary(forKey: "shortcuts") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "shortcuts") }
    }
    /// Export: a marp-cli to use instead of the one found (a binary or its folder), and a browser marp-cli
    /// cannot find on its own. Empty means "find it".
    static var marpPath: String {
        get { defaults.string(forKey: "marpPath") ?? "" }
        set { defaults.set(newValue, forKey: "marpPath") }
    }
    static var browserPath: String {
        get { defaults.string(forKey: "exportBrowserPath") ?? "" }
        set { defaults.set(newValue, forKey: "exportBrowserPath") }
    }
    /// The last export's choices, so the sheet opens the way it was left.
    static var exportOptions: ExportOptions {
        get {
            var o = ExportOptions()
            if let f = defaults.string(forKey: "exportFormat").flatMap(ExportFormat.init(rawValue:)) { o.format = f }
            o.pdfNotes = defaults.bool(forKey: "exportPdfNotes")
            o.pdfOutlines = defaults.object(forKey: "exportPdfOutlines") as? Bool ?? true
            o.pptxEditable = defaults.bool(forKey: "exportPptxEditable")
            return o
        }
        set {
            defaults.set(newValue.format.rawValue, forKey: "exportFormat")
            defaults.set(newValue.pdfNotes, forKey: "exportPdfNotes")
            defaults.set(newValue.pdfOutlines, forKey: "exportPdfOutlines")
            defaults.set(newValue.pptxEditable, forKey: "exportPptxEditable")
        }
    }
    static var checklistHidden: Bool {
        get { defaults.bool(forKey: "gettingStartedHidden") }
        set { defaults.set(newValue, forKey: "gettingStartedHidden") }
    }
    /// Where the user was: course and unit, even with no file open, so a relaunch lands on the same screen.
    static var lastCourse: String {
        get { defaults.string(forKey: "lastCourse") ?? "" }
        set { defaults.set(newValue, forKey: "lastCourse") }
    }
    static var lastUnit: String? {
        get { defaults.string(forKey: "lastUnit") }
        set { if let newValue { defaults.set(newValue, forKey: "lastUnit") } else { defaults.removeObject(forKey: "lastUnit") } }
    }
    static var lastFile: String {
        get { defaults.string(forKey: "lastFile") ?? "" }
        set { defaults.set(newValue, forKey: "lastFile") }
    }
    /// Where the session id lived before the chat archive (0.1.3); seeds a scope that has no archived conversation.
    static func sessionId(for key: String) -> String? { defaults.string(forKey: "oberik-session:\(key.isEmpty ? "_" : key)") }

    /// The project root of this checkout, when the app runs from `swift run` inside it.
    static var devProjectRoot: URL? {
        var u = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("skill-pack").path) { return u }
            u.deleteLastPathComponent()
        }
        // A packaged app starts with cwd "/"; the checkout usually sits next to the lecture repo.
        if let repo = repoPath {
            let sib = URL(fileURLWithPath: repo).deletingLastPathComponent().appendingPathComponent("lecture-studio")
            if FileManager.default.fileExists(atPath: sib.appendingPathComponent("skill-pack").path) { return sib }
        }
        return nil
    }

    /// Default repo: `$LECTURE_REPO` or the saved path; otherwise the app asks for a folder.
    static func defaultRepo() -> URL? {
        if let env = ProcessInfo.processInfo.environment["LECTURE_REPO"], !env.isEmpty { return URL(fileURLWithPath: env) }
        if let p = repoPath, FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    /// Copy the Oberik credentials out of the project's `.env` (development convenience).
    @discardableResult
    static func importDotEnv() -> Bool {
        guard let root = devProjectRoot, let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) else { return false }
        let env = DotEnv.parse(text)
        var any = false
        if let id = env["OBERIK_PROJECT_ID"], !id.isEmpty { projectId = id; any = true }
        if let key = env["OBERIK_PROJECT_KEY"] ?? env["OBERIK_API_KEY"], !key.isEmpty { projectKey = key; any = true }
        if let s = env["OBERIK_SUBJECT"], !s.isEmpty { subject = s }
        return any
    }

    static var hasOberik: Bool { !projectId.isEmpty && !projectKey.isEmpty }
}

/// The project key. A signed .app uses the Keychain; a bare `swift build` executable cannot (every rebuild
/// changes its ad-hoc signature, and the Keychain would block the main thread with a consent dialog), so
/// it keeps the key in a 0600 file under Application Support instead.
enum Keychain {
    static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func fileURL(_ account: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LectureStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent(account)
    }

    static func read(service: String, account: String) -> String? {
        if !isBundledApp { return (try? String(contentsOf: fileURL(account), encoding: .utf8))?.trimmed }
        return readKeychain(service: service, account: account)
    }

    static func write(service: String, account: String, value: String) {
        if !isBundledApp {
            let u = fileURL(account)
            if value.isEmpty { try? FileManager.default.removeItem(at: u); return }
            try? Data(value.utf8).write(to: u, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
            return
        }
        writeKeychain(service: service, account: account, value: value)
    }

    static func readKeychain(service: String, account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func writeKeychain(service: String, account: String, value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        if value.isEmpty { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
