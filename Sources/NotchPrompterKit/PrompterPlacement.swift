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

/// Where the prompter panel goes, and how far down its text starts.
///
/// The panel grows out of the notch. Its top edge is the screen's top edge,
/// it is centred on the notch, and it is filled black, so it reads as the
/// hardware notch getting bigger. At the top it flares into the screen edge
/// with a concave "ear" on each side, so the frame is one ``earRadius``
/// wider than the body on each side. The text starts ``topInset`` below the
/// top edge, just under the camera housing.
///
/// On a display without a notch the same shape hangs from the top centre,
/// over the middle of the menu bar, with a small inset so the text sits as
/// high as the screen allows.
public struct PrompterPlacement: Equatable, Sendable {

    /// The radius of the concave curves where the panel meets the top edge.
    public static let earRadius: CGFloat = 10
    /// The radius of the panel's rounded bottom corners.
    public static let bottomCornerRadius: CGFloat = 20
    /// Space above the text on a display without a notch.
    public static let topInsetWithoutNotch: CGFloat = 6

    /// The panel frame, in AppKit screen coordinates.
    public let frame: CGRect
    /// How far below the frame's top edge the text area starts: the notch
    /// height, or ``topInsetWithoutNotch``.
    public let topInset: CGFloat

    /// Places the panel on `display` around a text area of `textArea` size.
    ///
    /// The body is never narrower than the notch, so the notch is always
    /// covered. On a display too small for the panel, the panel shrinks,
    /// keeping `margin` from the side edges and its top edge at the top.
    public init(on display: DisplayGeometry, textArea: CGSize, margin: CGFloat = 8) {
        let screen = display.frame
        let notch = display.notch
        let topInset = notch?.height ?? Self.topInsetWithoutNotch
        let bodyWidth = max(textArea.width, notch?.width ?? 0)
        let width = max(0, min(bodyWidth + 2 * Self.earRadius, screen.width - 2 * margin)).rounded()
        let height = max(0, min(topInset + textArea.height, screen.height)).rounded()
        let centerX = notch?.midX ?? screen.midX
        let minX = screen.minX + margin
        let maxX = screen.maxX - margin - width
        let x = min(max(centerX - width / 2, minX), max(minX, maxX))
        self.frame = CGRect(x: x.rounded(), y: screen.maxY - height, width: width, height: height)
        self.topInset = topInset
    }
}
