import Foundation

/// A keyboard shortcut the user can change: one key plus modifiers. The pure part lives here so the
/// encoding and the defaults are testable; the AppKit and SwiftUI bridges are in the app.
public struct Shortcut: Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let control = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    /// A lowercase character ("b", "1", "/") or a special key name from `Shortcut.specialKeys`.
    public var key: String
    public var modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Special keys: name → glyph shown to the user.
    public static let specialKeys: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "escape": "⎋", "space": "Space", "return": "↩",
        "tab": "⇥", "delete": "⌫", "pageUp": "⇞", "pageDown": "⇟", "home": "↖", "end": "↘",
        "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4", "f5": "F5", "f6": "F6",
        "f7": "F7", "f8": "F8", "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
    ]

    public var isSpecialKey: Bool { Shortcut.specialKeys[key] != nil }

    /// "⌘B", "⌃⌥→", "⎋".
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Shortcut.specialKeys[key] ?? key.uppercased())
    }

    /// "cmd+opt+p", "right": the form kept in the defaults.
    public func encode() -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    public static func decode(_ s: String) -> Shortcut? {
        var body = s
        let key: String
        if s == "+" || s.hasSuffix("++") {
            // "cmd++" is the plus key.
            key = "+"
            body = String(body.dropLast(2))
        } else {
            let parts = body.split(separator: "+", omittingEmptySubsequences: false)
            guard let last = parts.last, !last.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }
            key = String(last)
            body = parts.dropLast().joined(separator: "+")
        }
        let parts = body.isEmpty ? [] : body.split(separator: "+").map(String.init)
        var mods: Modifiers = []
        for p in parts {
            switch p {
            case "cmd": mods.insert(.command)
            case "opt": mods.insert(.option)
            case "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        guard specialKeys[key] != nil || key.count == 1 else { return nil }
        return Shortcut(key, mods)
    }

    /// A shortcut a menu can carry without stealing typing: a special key, or a key with a modifier
    /// other than Shift alone.
    public var isUsable: Bool { isSpecialKey || !modifiers.subtracting(.shift).isEmpty }
}

/// Everything the user can put a shortcut on.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case save, exportDeck, refreshLibrary, startPresenting, nextSlide, previousSlide, endPresentation, toggleBreak, toggleCountdown
    case toggleChat, togglePreview, toggleEditor, toggleNotes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .save: "Save"
        case .exportDeck: "Export…"
        case .refreshLibrary: "Refresh Library"
        case .startPresenting: "Start Presenting"
        case .nextSlide: "Next Slide"
        case .previousSlide: "Previous Slide"
        case .endPresentation: "End Presentation"
        case .toggleBreak: "Break (start or end)"
        case .toggleCountdown: "Lecture Timer (start or stop)"
        case .toggleChat: "Show or Hide Chat"
        case .togglePreview: "Show or Hide Preview"
        case .toggleEditor: "Show or Hide Editor"
        case .toggleNotes: "Speaker Notes"
        }
    }

    public var defaultShortcut: Shortcut? {
        switch self {
        case .save: Shortcut("s", .command)
        case .exportDeck: Shortcut("e", [.command, .shift])
        case .refreshLibrary: Shortcut("r", .command)
        case .startPresenting: Shortcut("p", [.command, .option])
        case .nextSlide: Shortcut("right")
        case .previousSlide: Shortcut("left")
        case .endPresentation: Shortcut("escape")
        case .toggleBreak: Shortcut("b", .command)
        case .toggleCountdown: nil
        case .toggleChat: Shortcut("1", [.command, .option])
        case .togglePreview: Shortcut("2", [.command, .option])
        case .toggleEditor: Shortcut("3", [.command, .option])
        case .toggleNotes: nil
        }
    }

    /// The presenter's own keys (next, previous, end, break, timer) work while the slides are up.
    public var isPresenterKey: Bool {
        switch self {
        case .nextSlide, .previousSlide, .endPresentation, .toggleBreak, .toggleCountdown: true
        default: false
        }
    }
}

/// The shortcut table: defaults, with the user's changes on top. An empty override means "no shortcut".
public struct ShortcutTable: Equatable, Sendable {
    public var overrides: [String: String]

    public init(overrides: [String: String] = [:]) { self.overrides = overrides }

    public func shortcut(for a: ShortcutAction) -> Shortcut? {
        if let o = overrides[a.rawValue] { return o.isEmpty ? nil : Shortcut.decode(o) }
        return a.defaultShortcut
    }

    public func isDefault(_ a: ShortcutAction) -> Bool { overrides[a.rawValue] == nil }

    public mutating func set(_ s: Shortcut?, for a: ShortcutAction) {
        if s == a.defaultShortcut { overrides[a.rawValue] = nil } else { overrides[a.rawValue] = s?.encode() ?? "" }
    }

    public mutating func reset(_ a: ShortcutAction) { overrides[a.rawValue] = nil }

    /// The action that already uses this shortcut, if any.
    public func owner(of s: Shortcut, except: ShortcutAction? = nil) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != except && shortcut(for: $0) == s }
    }
}
