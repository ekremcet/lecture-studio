import SwiftUI
import AppKit
import StudioCore

/// Presenter mode: a borderless black window with the current slide on the second screen, and a presenter
/// window with the current slide, the next slide, the speaker notes, a clock and the slide counter. Arrow
/// keys and space move; Escape ends.
///
/// With one screen (a laptop alone, or mirrored to the projector) the slide window takes that screen at
/// the normal window level, so the menu bar still drops down, ⌘Tab still brings another app on top and
/// the Dock still comes up. A control strip appears over the slide when the pointer reaches the bottom
/// of the screen and hides again a few seconds after it leaves; the presenter window opens over the slide
/// on request instead of at the start.
@MainActor @Observable
final class Presentation {
    private(set) var presenting = false
    /// One screen: the slide window is on the screen the presenter looks at.
    private(set) var singleScreen = false
    /// The control strip over the slide (single screen) stays until this time, or while hovered.
    private(set) var stripUntil: Date?
    private(set) var stripHovered = false
    private(set) var presenterShown = false
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
    private var pointerTimer: Timer?
    private var stripTimer: Timer?
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

    /// Single screen: show the presenter window over the slide, or hide it again.
    func togglePresenterWindow() {
        guard presenting, singleScreen, let p = presenterWindow else { return }
        if presenterShown { p.orderOut(nil); presenterShown = false; showWindow?.makeKey() }
        else { p.makeKeyAndOrderFront(nil); presenterShown = true }
    }

    /// The strip's home: the pointer this close to the bottom of the slide brings it up.
    static let stripZone: CGFloat = 140

    /// Where the pointer is, in screen coordinates. Polled, not taken from mouse-moved events: those reach
    /// the slide window only while it is key, and not at all over the web view.
    func pointer(at p: NSPoint) {
        guard presenting, singleScreen, let w = showWindow, w.frame.contains(p) else { return }
        if p.y < w.frame.minY + Self.stripZone { showStrip() }
    }

    /// The control strip shows for a few seconds once the pointer reaches the bottom; the pointer hides
    /// when it goes. Polls come ten times a second, so the timer is only pushed once it has less than a
    /// second left.
    private func showStrip(for seconds: TimeInterval = 3) {
        if let u = stripUntil, u.timeIntervalSinceNow > seconds - 1 { return }
        stripUntil = Date().addingTimeInterval(seconds)
        stripTimer?.invalidate()
        stripTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideStrip() }
        }
    }

    private func hideStrip() {
        guard presenting, singleScreen else { return }
        if stripHovered { showStrip(); return }
        stripUntil = nil
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func setStripHovered(_ h: Bool) {
        stripHovered = h
        if h { stripUntil = .distantFuture; stripTimer?.invalidate() } else { stripUntil = nil; showStrip() }
    }

    var stripVisible: Bool { stripUntil.map { $0 > Date() } ?? false }

    func next() { guard presenting, index + 1 < count else { return }; index += 1; apply() }
    func previous() { guard presenting, index > 0 else { return }; index -= 1; apply() }
    func go(_ i: Int) { guard presenting, i >= 0, i < count else { return }; index = i; apply() }

    func stop() {
        guard presenting else { return }
        presenting = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        pointerTimer?.invalidate(); pointerTimer = nil
        stripTimer?.invalidate(); stripTimer = nil
        stripUntil = nil; stripHovered = false; presenterShown = false
        NSCursor.setHiddenUntilMouseMoves(false)
        NSApp.presentationOptions = []
        showWindow?.orderOut(nil); showWindow = nil
        presenterWindow?.orderOut(nil); presenterWindow = nil
        for c in [show, current, upcoming] { c.present(-1) }
    }

    private func openWindows() {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens[0]
        let external = screens.first { $0 != mainScreen } ?? mainScreen
        singleScreen = external == mainScreen
        // The slide window: borderless, black. On the other screen it sits above that screen's menu bar;
        // on the only screen it stays at the normal level so the menu bar, the Dock and ⌘Tab keep working.
        let w = ShowWindow(contentRect: external.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = .black
        if singleScreen {
            w.level = .normal
            w.collectionBehavior = [.fullScreenAuxiliary, .stationary]
            w.takesKeyboard = true
        } else {
            w.level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        }
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ShowView(presentation: self).ignoresSafeArea())
        w.setFrame(external.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        showWindow = w
        if singleScreen { NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock] }
        // The presenter window on this screen. With one screen it would cover the slide, so it waits
        // behind the strip's Notes button and floats over the slide when asked for.
        let frame = mainScreen.visibleFrame
        let size = NSSize(width: min(1180, frame.width - 80), height: min(720, frame.height - 80))
        let p = NSWindow(contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        p.title = "Presenter"
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: PresenterView(presentation: self))
        presenterWindow = p
        if singleScreen {
            p.level = .floating
            presenterShown = false
            showStrip()
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pointer(at: NSEvent.mouseLocation) }
            }
        } else {
            p.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // One screen: closing the notes only puts them away; the slide stays up.
                if self.singleScreen { self.presenterShown = false; self.showWindow?.makeKey() } else { self.stop() }
            }
        }
    }
}

/// The slide window. On one screen it takes the keyboard, so the strip's field and the presenter keys work
/// with no other window of the app in front; on two the presenter window keeps it, as before.
final class ShowWindow: NSWindow {
    var takesKeyboard = false
    override var canBecomeKey: Bool { takesKeyboard }
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

    var breakControl: some View { BreakControl(presentation: presentation) }

    func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(presentation.startedAt)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}

/// The minutes field and Break, or the running countdown and End break. Shared by the presenter window
/// and the single-screen strip.
struct BreakControl: View {
    let presentation: Presentation
    @State private var breakText = "10"

    var body: some View {
        if let until = presentation.breakUntil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                Text("Break \(String(format: "%d:%02d", left / 60, left % 60))").font(.title3.monospacedDigit()).foregroundStyle(.orange)
                    .onChange(of: left) { _, v in if v == 0 { presentation.endBreak() } }
            }
            Button("End break") { presentation.endBreak() }.fixedSize()
        } else {
            HStack(spacing: 4) {
                TextField("min", text: $breakText).frame(width: 40).multilineTextAlignment(.trailing).onSubmit { startBreak() }
                Button { startBreak() } label: { Label("Break", systemImage: "cup.and.saucer") }.fixedSize()
                    .help("Show a countdown on the audience screen for this many minutes")
            }
        }
    }

    func startBreak() { presentation.startBreak(minutes: Int(breakText.trimmed) ?? 10) }
}

/// Single screen: the presenter's controls over the slide, shown while the mouse moves.
struct ControlStrip: View {
    let presentation: Presentation

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Button { presentation.previous() } label: { Image(systemName: "chevron.left") }.disabled(presentation.index == 0)
                Text("\(presentation.index + 1) / \(presentation.count)").font(.title3.monospacedDigit())
                Button { presentation.next() } label: { Image(systemName: "chevron.right") }.disabled(presentation.index + 1 >= presentation.count)
            }
            TimelineView(.periodic(from: presentation.startedAt, by: 1)) { ctx in
                let s = max(0, Int(ctx.date.timeIntervalSince(presentation.startedAt)))
                Text(String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
            BreakControl(presentation: presentation)
            Button { presentation.togglePresenterWindow() } label: { Label(presentation.presenterShown ? "Hide notes" : "Notes", systemImage: "text.alignleft") }.fixedSize()
                .help("The presenter window: the next slide and your notes, over the slide")
            Button("End", role: .destructive) { presentation.stop() }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        .onHover { presentation.setStripHovered($0) }
    }
}

/// The audience screen: the slide, or the break card while a break runs. With one screen the control
/// strip sits at the bottom while the mouse moves.
struct ShowView: View {
    let presentation: Presentation

    var body: some View {
        ZStack {
            WebViewHost(webView: presentation.show.webView)
            if let until = presentation.breakUntil {
                BreakView(presentation: presentation, until: until)
            }
            if presentation.singleScreen {
                VStack {
                    Spacer()
                    ControlStrip(presentation: presentation).padding(.bottom, 28)
                        .opacity(presentation.stripVisible ? 1 : 0)
                        .allowsHitTesting(presentation.stripVisible)
                        .animation(.easeOut(duration: 0.2), value: presentation.stripVisible)
                }
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
