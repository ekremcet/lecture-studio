import SwiftUI
import AppKit
import StudioCore
import WebKit
import ScreenCaptureKit

@main
struct LectureStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let store = StudioStore.shared

    var body: some Scene {
        // A single window: no tabs, no "New Window".
        Window("Lecture Studio", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { Smoke.run(store: store) }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(after: .saveItem) {
                Button("Save") { Task { await store.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.dirty)
            }
            // Menus follow the screen: View and Present exist only in the workspace.
            if store.stage == .work {
                CommandMenu("View") {
                    Button("Refresh Library") { Task { await store.refreshLibrary() } }.keyboardShortcut("r", modifiers: .command)
                    Divider()
                    ForEach(PanelId.allCases) { p in
                        Toggle(p.rawValue.capFirst, isOn: Binding(get: { !store.hiddenPanels.contains(p) }, set: { _ in store.togglePanel(p) }))
                            .keyboardShortcut(KeyEquivalent(Character(String(PanelId.allCases.firstIndex(of: p)! + 1))), modifiers: [.command, .option])
                    }
                    Toggle("Speaker Notes", isOn: Binding(get: { store.showNotes }, set: { _ in store.toggleNotes() }))
                    Divider()
                    Button("Reset Layout") { store.resetLayout() }
                    Divider()
                    Button("Presenter Profile…") { store.dialog = .profile }
                }
            }
            CommandGroup(replacing: .help) {
                Button("How Decks Work (Marp)") { store.dialog = .marpHelp }
                Button("Marp Markdown Reference") { NSWorkspace.shared.open(URL(string: "https://marpit.marp.app/markdown")!) }
            }
            if store.stage == .work {
                CommandMenu("Present") {
                    Button("Start Presenting") { store.startPresentation() }
                        .keyboardShortcut("p", modifiers: [.command, .option])
                        .disabled(!store.canPresent)
                    Button("Next Slide") { store.presentation.next() }.keyboardShortcut(.rightArrow, modifiers: []).disabled(!store.presentation.presenting)
                    Button("Previous Slide") { store.presentation.previous() }.keyboardShortcut(.leftArrow, modifiers: []).disabled(!store.presentation.presenting)
                    Button("End Presentation") { store.presentation.stop() }.keyboardShortcut(.escape, modifiers: []).disabled(!store.presentation.presenting)
                }
            }
        }
        Settings {
            SettingsView().environment(store)
        }
    }
}

/// A Swift Package executable has no app bundle, so the window would open behind the terminal.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One library, one window: window tabs would only show the same screen twice.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows { w.tabbingMode = .disallowed }
        Snapshot.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Development aid: `STUDIO_SNAPSHOT=/dir` writes the main window and its web views to PNG files
/// every few seconds, so a build can be checked without screen-recording permission.
enum Snapshot {
    static func start() {
        guard let dir = ProcessInfo.processInfo.environment["STUDIO_SNAPSHOT"], !dir.isEmpty else { return }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in await capture(to: URL(fileURLWithPath: dir)) }
        }
    }

    @MainActor
    static func capture(to dir: URL) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = window.contentView else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // ScreenCaptureKit draws the window as the user sees it, web views included.
        var captureNote = ""
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let w = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let filter = SCContentFilter(desktopIndependentWindow: w)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(w.frame.width * window.backingScaleFactor)
                cfg.height = Int(w.frame.height * window.backingScaleFactor)
                cfg.showsCursor = false
                let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: dir.appendingPathComponent("window.png")) }
            } else { captureNote = "window not in shareable content" }
        } catch { captureNote = "capture failed: \(error)" }
        var dump = "\(captureNote)\nwindow=\(window.title) frame=\(window.frame) visible=\(window.isVisible) key=\(window.isKeyWindow) windows=\(NSApp.windows.count)\n"
        func walk(_ v: NSView, _ depth: Int) {
            dump += String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) layer=\(v.layer != nil)\n"
            for s in v.subviews { walk(s, depth + 1) }
        }
        walk(view, 0)
        try? dump.write(to: dir.appendingPathComponent("hierarchy.txt"), atomically: true, encoding: .utf8)
        var i = 0
        for wv in webViews(in: view) where wv.frame.width > 10 {
            i += 1
            let cfg = WKSnapshotConfiguration()
            if let img = try? await wv.takeSnapshot(configuration: cfg), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("web\(i).png"))
            }
        }
    }

    static func webViews(in v: NSView) -> [WKWebView] {
        var out: [WKWebView] = []
        if let w = v as? WKWebView { out.append(w) }
        for s in v.subviews { out += webViews(in: s) }
        return out
    }
}
