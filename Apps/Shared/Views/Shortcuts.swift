import SwiftUI

/// The Prompter menu's keyboard shortcuts, shared with the toolbar tooltips
/// so the two never disagree.
enum Shortcuts {
    static let togglePrompter = KeyboardShortcut("p", modifiers: [.command, .shift])
    static let record = KeyboardShortcut("r", modifiers: .command)
    static let rehearse = KeyboardShortcut("r", modifiers: [.command, .shift])
    static let stop = KeyboardShortcut(".", modifiers: .command)
}

extension KeyboardShortcut {

    /// The shortcut as a menu shows it, for example "⇧⌘P".
    var label: String {
        let symbols: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + String(key.character).uppercased()
    }
}
