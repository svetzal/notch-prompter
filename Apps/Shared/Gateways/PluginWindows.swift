import AppKit
import NotchPrompterKit

/// One window for each open plug-in, keyed by the chain entry, showing the
/// plug-in's own interface.
///
/// A thin adapter over `NSWindow`. The window opens at the size the Kit's
/// ``PluginWindowSize`` picks. A plug-in whose view stretches can be resized
/// by the presenter. A plug-in that resizes itself, for example from a
/// handle in its own interface, resizes the window with it. Closing a window
/// reports back, so the plug-in's settings can be saved and the plug-in
/// released.
@MainActor
final class PluginWindows {

    private var windows: [UUID: PluginWindow] = [:]

    /// Brings the entry's window to the front. False when it has none.
    func bringToFront(_ id: UUID) -> Bool {
        guard let window = windows[id] else { return false }
        window.window.makeKeyAndOrderFront(nil)
        return true
    }

    func show(_ controller: NSViewController, id: UUID, title: String, onClose: @escaping @MainActor () -> Void) {
        let window = PluginWindow(controller: controller, title: title) { [weak self] in
            self?.windows[id] = nil
            onClose()
        }
        windows[id] = window
        window.window.center()
        window.window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: UUID) {
        windows[id]?.window.close()
    }
}

/// A plug-in's window, and the observers that keep it the plug-in's size.
@MainActor
private final class PluginWindow: NSObject, NSWindowDelegate {

    let window: NSWindow
    private let controller: NSViewController
    /// The view whose size is the plug-in's own: the single view that a
    /// classic Cocoa interface puts inside its view controller, or the
    /// controller's view.
    private let pluginView: NSView
    private let onClose: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []
    private var preferredSizeObservation: NSKeyValueObservation?

    init(controller: NSViewController, title: String, onClose: @escaping @MainActor () -> Void) {
        self.controller = controller
        self.onClose = onClose
        let view = controller.view
        pluginView = view.subviews.count == 1 ? view.subviews[0] : view
        let stretches = pluginView.autoresizingMask.contains(.width) || pluginView.autoresizingMask.contains(.height)
        window = NSWindow(
            contentRect: .zero,
            styleMask: stretches ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(PluginWindowSize.initial(preferred: controller.preferredContentSize, view: pluginView.frame.size))
        window.delegate = self
        followPluginSize()
    }

    /// Resizes the window when the plug-in changes its own size or its
    /// preferred size.
    private func followPluginSize() {
        pluginView.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: pluginView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fit(self?.pluginView.frame.size) }
        })
        preferredSizeObservation = controller.observe(\.preferredContentSize) { [weak self] _, _ in
            Task { @MainActor in self?.fit(self?.controller.preferredContentSize) }
        }
    }

    private func fit(_ size: CGSize?) {
        guard let size, let followed = PluginWindowSize.followed(size), window.contentLayoutRect.size != followed else { return }
        window.setContentSize(followed)
    }

    func windowWillClose(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        preferredSizeObservation = nil
        onClose()
    }
}
