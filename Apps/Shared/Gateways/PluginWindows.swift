import AppKit
import SwiftUI

/// One window for each open plug-in editor, keyed by the chain entry.
///
/// A thin adapter over `NSWindow`. Closing a window reports back, so the
/// plug-in's settings can be saved and the plug-in released.
@MainActor
final class PluginWindows {

    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: CloseObserver] = [:]

    /// The smallest content size that gives a plug-in's own view room, and
    /// the size used when a plug-in does not say what it needs.
    private static let minimumSize = CGSize(width: 420, height: 260)
    private static let defaultSize = CGSize(width: 480, height: 420)
    /// Room for the switch between the plug-in's view and its parameters.
    private static let headerHeight: CGFloat = 44

    /// Brings the entry's window to the front. False when it has none.
    func bringToFront(_ id: UUID) -> Bool {
        guard let window = windows[id] else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func show(_ editor: PluginEditor, onClose: @escaping @MainActor () -> Void) {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.contentSize(for: editor)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(editor.component.name) Settings"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: PluginEditorView(editor: editor))
        // The window keeps the size chosen here; the plug-in's view does not resize it.
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(Self.contentSize(for: editor))
        let id = editor.id
        let observer = CloseObserver { [weak self] in
            self?.windows[id] = nil
            self?.delegates[id] = nil
            onClose()
        }
        window.delegate = observer
        windows[id] = window
        delegates[id] = observer
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: UUID) {
        windows[id]?.close()
    }

    func closeAll() {
        for window in windows.values {
            window.close()
        }
    }

    private static func contentSize(for editor: PluginEditor) -> CGSize {
        guard let preferred = editor.viewController?.preferredContentSize,
              preferred.width >= 50, preferred.height >= 50 else {
            return defaultSize
        }
        return CGSize(
            width: max(preferred.width, minimumSize.width),
            height: max(preferred.height + headerHeight, minimumSize.height)
        )
    }
}

/// Reports a window's close.
private final class CloseObserver: NSObject, NSWindowDelegate {

    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose() }
    }
}
