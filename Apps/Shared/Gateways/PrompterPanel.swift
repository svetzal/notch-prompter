import AppKit
import SwiftUI

/// The borderless window that holds the prompter text under the camera.
///
/// It floats above the menu bar, appears on every Space and over full-screen
/// apps, never takes focus, and lets clicks pass through. Keyboard control
/// comes from ``PrompterKeyMonitor`` instead, so the main window keeps focus.
final class PrompterPanel: NSPanel {

    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(in frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
