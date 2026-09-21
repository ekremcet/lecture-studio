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
                .onOpenURL { url in store.handleURL(url) }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(after: .saveItem) {
                Button("Save") { Task { await store.save() } }
                    .keyboardShortcut(store.shortcut(for: .save)?.keyboardShortcut)
                    .disabled(!store.dirty)
                Divider()
                Button("Export…") { store.exportDeck() }
                    .keyboardShortcut(store.shortcut(for: .exportDeck)?.keyboardShortcut)
                    .disabled(!store.canExport)
            }
            // Menus follow the screen: View and Present exist only in the workspace.
            if store.stage == .work {
                CommandMenu("View") {
                    Button("Refresh Library") { Task { await store.refreshLibrary() } }.keyboardShortcut(store.shortcut(for: .refreshLibrary)?.keyboardShortcut)
                    Divider()
                    ForEach(PanelId.allCases) { p in
                        Toggle(p.rawValue.capFirst, isOn: Binding(get: { !store.hiddenPanels.contains(p) }, set: { _ in store.togglePanel(p) }))
                            .keyboardShortcut(store.shortcut(for: store.shortcutAction(for: p))?.keyboardShortcut)
                    }
                    Toggle("Speaker Notes", isOn: Binding(get: { store.showNotes }, set: { _ in store.toggleNotes() }))
                        .keyboardShortcut(store.shortcut(for: .toggleNotes)?.keyboardShortcut)
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
                        .keyboardShortcut(store.shortcut(for: .startPresenting)?.keyboardShortcut)
                        .disabled(!store.canPresent)
                    Button("Next Slide") { store.presentation.next() }.keyboardShortcut(store.shortcut(for: .nextSlide)?.keyboardShortcut).disabled(!store.presentation.presenting)
                    Button("Previous Slide") { store.presentation.previous() }.keyboardShortcut(store.shortcut(for: .previousSlide)?.keyboardShortcut).disabled(!store.presentation.presenting)
                    // One screen only: on two the presenter window is always up.
                    Button(store.presentation.presenterShown ? "Hide Presenter Window" : "Show Presenter Window") { store.presentation.togglePresenterWindow() }
                        .disabled(!store.presentation.presenting || !store.presentation.singleScreen)
                    Divider()
                    Button(store.presentation.breakUntil == nil ? "Take a Break" : "End Break") { store.presentation.toggleBreak() }
                        .keyboardShortcut(store.shortcut(for: .toggleBreak)?.keyboardShortcut).disabled(!store.presentation.presenting)
                    Button(store.presentation.countdown.running ? "Stop the Lecture Timer" : "Start the Lecture Timer") { store.presentation.toggleCountdown() }
                        .keyboardShortcut(store.shortcut(for: .toggleCountdown)?.keyboardShortcut).disabled(!store.presentation.presenting || store.presentation.breakUntil != nil)
                    Divider()
                    Button("End Presentation") { store.presentation.stop() }.keyboardShortcut(store.shortcut(for: .endPresentation)?.keyboardShortcut).disabled(!store.presentation.presenting)
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

    /// ⌘Q asks first. A stray ⌘Q while typing would otherwise drop the session, and the deck's unsaved
    /// edits with it, so the dirty deck also gets a "Save and Quit".
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = StudioStore.shared
        // Closing the window is already a deliberate exit; only unsaved edits still warrant a question.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }), !store.dirty { return .terminateNow }
        // The slide window floats above the alert level; end the show so the question is visible.
        if store.presentation.presenting { store.presentation.stop() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if store.dirty {
            alert.messageText = "Quit Lecture Studio?"
            alert.informativeText = "\(store.filePath) has unsaved changes."
            alert.addButton(withTitle: "Save and Quit")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Without Saving")
        } else {
            alert.messageText = "Quit Lecture Studio?"
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
        }
        alert.buttons[1].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard store.dirty else { return .terminateNow }
            Task { @MainActor in
                await store.save()
                // Save reports its own failure as a toast; do not quit over a deck it could not write.
                NSApp.reply(toApplicationShouldTerminate: !store.dirty)
            }
            return .terminateLater
        case .alertThirdButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }
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

    /// One window as the user sees it (web views included, other windows in front left out), or why not.
    @MainActor
    static func captureWindow(_ window: NSWindow, to file: URL) async -> String {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let w = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return "window not in shareable content" }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            cfg.width = Int(w.frame.width * window.backingScaleFactor)
            cfg.height = Int(w.frame.height * window.backingScaleFactor)
            cfg.showsCursor = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: file) }
            return ""
        } catch { return "capture failed: \(error)" }
    }

    @MainActor
    static func capture(to dir: URL) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = window.contentView else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let captureNote = await captureWindow(window, to: dir.appendingPathComponent("window.png"))
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
