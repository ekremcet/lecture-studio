import SwiftUI
import AppKit
import StudioCore

/// Presenter mode: a borderless black window with the current slide on the second screen (or this one
/// when there is only one), and a presenter window with the current slide, the next slide, the speaker
/// notes, a clock and the slide counter. Arrow keys and space move; Escape ends.
@MainActor @Observable
final class Presentation {
    private(set) var presenting = false
    private(set) var index = 0
    private(set) var count = 0
    private(set) var startedAt = Date()
    private(set) var notes: [String] = []
    private(set) var nextTitle = ""
    /// A break: the audience screen shows the course, the date and a countdown until this time.
    var breakUntil: Date?
    var breakMinutes = 10
    private(set) var courseTitle = ""
    private(set) var unitTitle = ""
    let show = PreviewController()
    let current = PreviewController()
    let upcoming = PreviewController()
    private var showWindow: NSWindow?
    private var presenterWindow: NSWindow?
    private var keyMonitor: Any?
    private weak var store: StudioStore?
    private var markdown = ""
    private var starts: [Int] = [0]

    func start(store: StudioStore, from: Int) {
        self.store = store
        courseTitle = Labels.courseLabel(store.course, store.meta)
        unitTitle = store.talk ? "" : Labels.unitLabel(store.unit ?? "")
        breakUntil = nil
        markdown = store.previewText
        starts = store.starts
        count = store.slideCount
        index = min(max(0, from), max(0, count - 1))
        startedAt = Date()
        presenting = true
        let dir = deckDir(store.filePath)
        Task {
            for c in [show, current, upcoming] { await c.render(markdown: markdown, deckDir: dir) }
            apply()
        }
        openWindows()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.presenting else { return e }
            switch e.keyCode {
            case 124, 125, 49, 121, 36: self.next(); return nil      // right, down, space, page down, return
            case 123, 126, 116: self.previous(); return nil          // left, up, page up
            case 53: self.stop(); return nil                          // escape
            default: return e
            }
        }
    }

    private func apply() {
        show.present(index)
        current.present(index)
        upcoming.present(index + 1 < count ? index + 1 : -2)
        notes = Slides.notes(markdown, starts: starts, index: index)
        store?.goToSlide(index, from: "rail")
    }

    func startBreak(minutes: Int) {
        breakMinutes = max(1, min(180, minutes))
        breakUntil = Date().addingTimeInterval(TimeInterval(breakMinutes * 60))
    }

    func endBreak() { breakUntil = nil }

    func next() { guard presenting, index + 1 < count else { return }; index += 1; apply() }
    func previous() { guard presenting, index > 0 else { return }; index -= 1; apply() }
    func go(_ i: Int) { guard presenting, i >= 0, i < count else { return }; index = i; apply() }

    func stop() {
        guard presenting else { return }
        presenting = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NSApp.presentationOptions = []
        showWindow?.orderOut(nil); showWindow = nil
        presenterWindow?.orderOut(nil); presenterWindow = nil
        for c in [show, current, upcoming] { c.present(-1) }
    }

    private func openWindows() {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens[0]
        let external = screens.first { $0 != mainScreen } ?? mainScreen
        // The slide window: borderless, black, above the menu bar of its screen.
        let w = NSWindow(contentRect: external.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = .black
        w.level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ShowView(presentation: self).ignoresSafeArea())
        w.setFrame(external.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        showWindow = w
        if external == mainScreen { NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock] }
        // The presenter window on this screen.
        let frame = mainScreen.visibleFrame
        let size = NSSize(width: min(1180, frame.width - 80), height: min(720, frame.height - 80))
        let p = NSWindow(contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        p.title = "Presenter"
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: PresenterView(presentation: self))
        p.makeKeyAndOrderFront(nil)
        presenterWindow = p
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in Task { @MainActor in self?.stop() } }
    }
}

struct PresenterView: View {
    let presentation: Presentation

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                WebViewHost(webView: presentation.current.webView)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button { presentation.previous() } label: { Image(systemName: "chevron.left") }.disabled(presentation.index == 0)
                    Text("\(presentation.index + 1) / \(presentation.count)").font(.title3.monospacedDigit())
                    Button { presentation.next() } label: { Image(systemName: "chevron.right") }.disabled(presentation.index + 1 >= presentation.count)
                    Spacer()
                    TimelineView(.periodic(from: presentation.startedAt, by: 1)) { ctx in
                        Text(elapsed(ctx.date)).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    breakControl
                    Button("End", role: .destructive) { presentation.stop() }.keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT").font(.caption2.weight(.medium)).tracking(0.6).foregroundStyle(.secondary)
                if presentation.index + 1 < presentation.count {
                    WebViewHost(webView: presentation.upcoming.webView).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("Last slide").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                Text("NOTES").font(.caption2.weight(.medium)).tracking(0.6).foregroundStyle(.secondary).padding(.top, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if presentation.notes.isEmpty {
                            Text("No notes on this slide.").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(presentation.notes.enumerated()), id: \.offset) { _, n in Text(n).textSelection(.enabled) }
                        }
                    }
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("← → or space to move, Esc to end").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(width: 380)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @State private var breakText = "10"

    /// Start a break of N minutes, or end the running one.
    @ViewBuilder var breakControl: some View {
        if let until = presentation.breakUntil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                Text("Break \(String(format: "%d:%02d", left / 60, left % 60))").font(.title3.monospacedDigit()).foregroundStyle(.orange)
                    .onChange(of: left) { _, v in if v == 0 { presentation.endBreak() } }
            }
            Button("End break") { presentation.endBreak() }
        } else {
            HStack(spacing: 4) {
                TextField("min", text: $breakText).frame(width: 36).multilineTextAlignment(.trailing).onSubmit { startBreak() }
                Button { startBreak() } label: { Label("Break", systemImage: "cup.and.saucer") }.help("Show a countdown on the audience screen for this many minutes")
            }
        }
    }

    func startBreak() {
        presentation.startBreak(minutes: Int(breakText.trimmed) ?? 10)
    }

    func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(presentation.startedAt)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}


/// The audience screen: the slide, or the break card while a break runs.
struct ShowView: View {
    let presentation: Presentation

    var body: some View {
        ZStack {
            WebViewHost(webView: presentation.show.webView)
            if let until = presentation.breakUntil {
                BreakView(presentation: presentation, until: until)
            }
        }
    }
}

struct BreakView: View {
    let presentation: Presentation
    let until: Date

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                VStack(spacing: unit * 0.04) {
                    Text(presentation.courseTitle).font(.system(size: unit * 0.06, weight: .semibold)).multilineTextAlignment(.center)
                    HStack(spacing: unit * 0.02) {
                        if !presentation.unitTitle.isEmpty { Text(presentation.unitTitle) }
                        Text(ctx.date.formatted(date: .long, time: .omitted))
                    }
                    .font(.system(size: unit * 0.035)).foregroundStyle(.secondary)
                    Spacer().frame(height: unit * 0.04)
                    Text("BREAK").font(.system(size: unit * 0.05, weight: .bold)).tracking(unit * 0.01).foregroundStyle(.orange)
                    Text(String(format: "%d:%02d", left / 60, left % 60)).font(.system(size: unit * 0.28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(left == 0 ? "Welcome back" : "Back in \(left / 60 + (left % 60 > 0 ? 1 : 0)) min").font(.system(size: unit * 0.035)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onChange(of: left) { _, v in if v == 0 { Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if presentation.breakUntil == until { presentation.endBreak() } } } }
            }
        }
    }
}
