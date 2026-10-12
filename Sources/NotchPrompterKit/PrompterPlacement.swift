import CoreGraphics

/// What the prompter needs to know about a display to sit under its camera.
///
/// All values come straight from `NSScreen`: `frame`, `safeAreaInsets.top`,
/// `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`. Rects are in AppKit
/// screen coordinates, origin at the bottom left, y increasing upwards.
public struct DisplayGeometry: Equatable, Sendable {

    public let frame: CGRect
    public let safeAreaTop: CGFloat
    public let auxiliaryTopLeft: CGRect
    public let auxiliaryTopRight: CGRect

    public init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeft: CGRect, auxiliaryTopRight: CGRect) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    /// The camera housing, in screen coordinates, or `nil` without a notch.
    ///
    /// The notch is what the two auxiliary areas leave between them. Only
    /// their widths are used, so the result does not depend on whether
    /// AppKit reports them in global or screen-local coordinates.
    public var notch: CGRect? {
        guard safeAreaTop > 0, !auxiliaryTopLeft.isEmpty, !auxiliaryTopRight.isEmpty else { return nil }
        let width = frame.width - auxiliaryTopLeft.width - auxiliaryTopRight.width
        guard width > 0 else { return nil }
        return CGRect(
            x: frame.minX + auxiliaryTopLeft.width,
            y: frame.maxY - safeAreaTop,
            width: width,
            height: safeAreaTop
        )
    }
}

/// Where the prompter panel goes.
public enum PrompterPlacement {

    /// The panel frame: centred under the notch with its top edge touching
    /// the notch's bottom, or at the top centre of a display without one.
    ///
    /// Without a notch, the panel covers the middle of the menu bar, which is
    /// as close to a top-mounted camera as the screen allows. The size shrinks
    /// to fit the display, keeping `margin` from the side edges.
    public static func frame(
        on display: DisplayGeometry,
        size: CGSize,
        margin: CGFloat = 8
    ) -> CGRect {
        let screen = display.frame
        let centerX = display.notch?.midX ?? screen.midX
        let top = display.notch?.minY ?? screen.maxY
        let width = max(0, min(size.width, screen.width - 2 * margin))
        let height = max(0, min(size.height, top - screen.minY))
        let minX = screen.minX + margin
        let maxX = screen.maxX - margin - width
        let x = min(max(centerX - width / 2, minX), max(minX, maxX))
        return CGRect(
            x: x.rounded(),
            y: (top - height).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }
}
