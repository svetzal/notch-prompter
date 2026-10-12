import AppKit
import NotchPrompterKit

/// Delivers prompter key presses while the app is frontmost.
///
/// A local event monitor sees keys before the focused view does, so space
/// and the arrows reach the prompter even with the main window in front.
/// It cannot see keys typed into other apps; that would need Accessibility
/// permission, which the prompter does not ask for.
@MainActor
final class PrompterKeyMonitor {

    /// Returns `true` when the key was used and should not reach the focused view.
    typealias Handler = @MainActor (PrompterKeyCommand) -> Bool
    /// Whether the prompter may take keys away from a focused text view.
    typealias Claims = @MainActor () -> Bool

    private var monitor: Any?

    func start(claimsKeysFromTextViews: @escaping Claims, handler: @escaping Handler) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let characters = event.charactersIgnoringModifiers else { return event }
            let modifiers = Self.modifiers(of: event.modifierFlags)
            let consumed = MainActor.assumeIsolated {
                Self.route(characters, modifiers, claimsKeysFromTextViews: claimsKeysFromTextViews, handler: handler)
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Returns `true` when the key was used.
    private static func route(
        _ characters: String,
        _ modifiers: PrompterKeyCommand.Modifiers,
        claimsKeysFromTextViews: Claims,
        handler: Handler
    ) -> Bool {
        guard let command = PrompterKeyCommand(characters: characters, modifiers: modifiers) else { return false }
        let typing = NSApp.keyWindow?.firstResponder is NSTextView
        if typing, !claimsKeysFromTextViews() {
            return false
        }
        return handler(command)
    }

    nonisolated private static func modifiers(of flags: NSEvent.ModifierFlags) -> PrompterKeyCommand.Modifiers {
        var result: PrompterKeyCommand.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
