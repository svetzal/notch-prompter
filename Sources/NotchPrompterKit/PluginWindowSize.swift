import CoreGraphics

/// The content size a plug-in's settings window opens at.
///
/// Plug-ins say what they need in different ways. An Audio Unit view
/// controller may set a preferred size; a classic Cocoa view comes at its
/// own frame size, with the preferred size left at zero; a view that has not
/// been laid out reports zero or one point. The first size that means
/// something wins.
public enum PluginWindowSize {

    /// The size for a plug-in that gives none.
    public static let fallback = CGSize(width: 480, height: 320)
    /// Sizes with a side smaller than this were never meant.
    static let smallestSide: CGFloat = 50

    public static func initial(preferred: CGSize, view: CGSize) -> CGSize {
        [preferred, view].first(where: isMeant) ?? fallback
    }

    /// The size to give the window when the plug-in changes its size to
    /// `size`, or `nil` when the change does not mean a size, such as a view
    /// collapsing to zero while it is taken down.
    public static func followed(_ size: CGSize) -> CGSize? {
        isMeant(size) ? size : nil
    }

    private static func isMeant(_ size: CGSize) -> Bool {
        size.width >= smallestSide && size.height >= smallestSide
    }
}
