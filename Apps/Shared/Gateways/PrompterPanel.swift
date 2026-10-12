import AppKit
import os
import SwiftUI

/// The borderless window that grows the prompter out of the notch.
///
/// Its top edge is the screen's top edge, so it covers the menu bar around
/// the notch. It floats above the menu bar and its status items, appears on
/// every Space and over full-screen apps, never takes focus, and lets clicks
/// pass through. Keyboard control comes from ``PrompterKeyMonitor`` instead,
/// so the main window keeps focus.
final class PrompterPanel: NSPanel {

    private static let log = Logger(subsystem: "com.mojility.notch-prompter", category: "panel")

    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        // Above the menu bar (.mainMenu) and its status items (.statusBar, one
        // higher), which would otherwise draw over the panel. Menus still open over it.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        // The view pads for the notch itself, from the placement.
        hosting.safeAreaRegions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit moves windows out from under the menu bar. The panel belongs
    /// there, so keep the frame exactly as placed.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func show(in frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
        if self.frame != frame {
            Self.log.error("Panel placed at \(String(describing: self.frame)), not \(String(describing: frame))")
        }
    }

    func hide() {
        orderOut(nil)
    }
}
