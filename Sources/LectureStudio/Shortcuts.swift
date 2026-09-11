import SwiftUI
import AppKit
import StudioCore

/// AppKit and SwiftUI faces of a `Shortcut`: reading one off a key event, handing one to a menu item,
/// and spotting a clash with a fixed menu item such as ⌘Q or ⌘Z.
extension Shortcut {
    private static let keyCodes: [UInt16: String] = [
        123: "left", 124: "right", 126: "up", 125: "down", 53: "escape", 49: "space", 36: "return", 48: "tab",
        51: "delete", 116: "pageUp", 121: "pageDown", 115: "home", 119: "end",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    /// The special keys as AppKit menu key equivalents (function-key code points, control characters).
    private static let menuChars: [String: String] = [
        "left": "\u{F702}", "right": "\u{F703}", "up": "\u{F700}", "down": "\u{F701}", "escape": "\u{1B}", "space": " ",
        "return": "\r", "tab": "\t", "delete": "\u{8}", "pageUp": "\u{F72C}", "pageDown": "\u{F72D}", "home": "\u{F729}", "end": "\u{F72B}",
        "f1": "\u{F704}", "f2": "\u{F705}", "f3": "\u{F706}", "f4": "\u{F707}", "f5": "\u{F708}", "f6": "\u{F709}",
        "f7": "\u{F70A}", "f8": "\u{F70B}", "f9": "\u{F70C}", "f10": "\u{F70D}", "f11": "\u{F70E}", "f12": "\u{F70F}",
    ]

    /// The shortcut a key press stands for. Letters are kept lowercase with Shift as a modifier; other
    /// shifted characters ("!", "+") stand on their own.
    static func from(_ e: NSEvent) -> Shortcut? {
        guard e.type == .keyDown else { return nil }
        var mods: Modifiers = []
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.command) { mods.insert(.command) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.control) { mods.insert(.control) }
        if f.contains(.shift) { mods.insert(.shift) }
        if let name = keyCodes[e.keyCode] { return Shortcut(name, mods) }
        guard let chars = e.charactersIgnoringModifiers, chars.count == 1, let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F, scalar.value < 0xF700 else { return nil }
        if chars.rangeOfCharacter(from: .letters) != nil { return Shortcut(chars.lowercased(), mods) }
        return Shortcut(chars, mods.subtracting(.shift))
    }

    func matches(_ e: NSEvent) -> Bool { Shortcut.from(e) == self }

    var keyboardShortcut: KeyboardShortcut {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        let k: KeyEquivalent = switch key {
        case "left": .leftArrow
        case "right": .rightArrow
        case "up": .upArrow
        case "down": .downArrow
        case "escape": .escape
        case "space": .space
        case "return": .return
        case "tab": .tab
        case "delete": .delete
        case "pageUp": .pageUp
        case "pageDown": .pageDown
        case "home": .home
        case "end": .end
        default: KeyEquivalent(Character(Shortcut.menuChars[key] ?? key))
        }
        return KeyboardShortcut(k, modifiers: m)
    }

    /// The shortcut an AppKit menu item carries, if any.
    static func of(_ item: NSMenuItem) -> Shortcut? {
        let ke = item.keyEquivalent
        guard !ke.isEmpty else { return nil }
        var mods: Modifiers = []
        let f = item.keyEquivalentModifierMask
        if f.contains(.command) { mods.insert(.command) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.control) { mods.insert(.control) }
        if f.contains(.shift) { mods.insert(.shift) }
        if let name = menuChars.first(where: { $0.value == ke || ($0.key == "delete" && ke == "\u{7F}") })?.key { return Shortcut(name, mods) }
        guard ke.count == 1 else { return nil }
        if ke.rangeOfCharacter(from: .uppercaseLetters) != nil { mods.insert(.shift) }
        return Shortcut(ke.lowercased(), mods)
    }

    /// The title of a fixed menu item that already uses this shortcut. Items that carry a configurable
    /// action are skipped: those clashes are reported by the shortcut table itself.
    @MainActor
    func menuCollision(table: ShortcutTable) -> String? {
        func walk(_ menu: NSMenu) -> String? {
            for item in menu.items {
                if let sub = item.submenu, let hit = walk(sub) { return hit }
                guard let s = Shortcut.of(item), s == self else { continue }
                if table.owner(of: s) != nil { continue }
                return item.title
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(walk)
    }
}

/// One row of the Shortcuts settings: click, type the new shortcut. Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    @Binding var message: String
    @Environment(StudioStore.self) private var store
    @State private var recording = false

    var body: some View {
        HStack(spacing: 6) {
            Button { message = ""; recording.toggle() } label: {
                Text(recording ? "Type a shortcut…" : (store.shortcut(for: action)?.display ?? "None"))
                    .foregroundStyle(recording ? Color.accentColor : (store.shortcut(for: action) == nil ? .secondary : .primary))
                    .frame(minWidth: 120)
            }
            .background(KeyCatcher(active: $recording, onKey: handle))
            if !store.shortcuts.isDefault(action) {
                Button("Reset") { store.setShortcut(action.defaultShortcut, for: action); message = "" }.controlSize(.small)
            }
        }
    }

    private func handle(_ e: NSEvent) {
        let plain = e.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection([.command, .option, .control, .shift]).isEmpty
        if plain && e.keyCode == 53 { recording = false; return }
        if plain && e.keyCode == 51 { store.setShortcut(nil, for: action); recording = false; return }
        guard let s = Shortcut.from(e) else { return }
        // Presenter keys may be bare (→, Space); anything else needs a real modifier or it steals typing.
        let bare = s.modifiers.subtracting(.shift).isEmpty
        if bare && !(action.isPresenterKey && s.isSpecialKey) { message = "\(s.display) would get in the way of typing. Add ⌘, ⌥ or ⌃."; return }
        if let owner = store.shortcuts.owner(of: s, except: action) { message = "\(s.display) is already \(owner.title)."; return }
        if let title = s.menuCollision(table: store.shortcuts) { message = "\(s.display) belongs to the \(title) menu item."; return }
        store.setShortcut(s, for: action)
        message = ""
        recording = false
    }
}

/// An invisible view that takes the keyboard while a recorder is active. It claims ⌘-keys before the
/// menu bar sees them, so typing ⌘S into the recorder does not save, and ⌘Q does not quit.
private struct KeyCatcher: NSViewRepresentable {
    @Binding var active: Bool
    var onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onKey = onKey
        v.onResign = { active = false }
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) {
        v.onKey = onKey
        v.onResign = { active = false }
        v.active = active
        let wantsFocus = active
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            if wantsFocus, w.firstResponder !== v { w.makeFirstResponder(v) }
            if !wantsFocus, w.firstResponder === v { w.makeFirstResponder(nil) }
        }
    }

    final class CatcherView: NSView {
        var active = false
        var onKey: (NSEvent) -> Void = { _ in }
        var onResign: () -> Void = {}
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { if active { onKey(event) } else { super.keyDown(with: event) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard active else { return super.performKeyEquivalent(with: event) }
            onKey(event)
            return true
        }
        override func resignFirstResponder() -> Bool {
            if active { onResign() }
            return super.resignFirstResponder()
        }
    }
}
