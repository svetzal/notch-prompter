import CoreGraphics
import Foundation

/// The shape of the movie a take records: wide for most video, tall for
/// phone-first video.
///
/// The camera is never turned. A take uses a camera format that already has
/// its shape when the camera has one (see ``NativeFormat``). Otherwise it is
/// cut from the centre of the camera's frame, so a tall take on a landscape
/// camera keeps the full height and loses width.
public enum VideoFormat: String, CaseIterable, Identifiable, Sendable {
    /// 16:9.
    case horizontal
    /// 9:16.
    case vertical

    /// How far a size's width-to-height ratio may stray, as a fraction of the
    /// format's ratio, and still count as the format's shape. Wide enough for
    /// the rounding to even pixel counts; far too narrow to mistake one
    /// format for the other.
    public static let shapeTolerance = 0.02

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }

    /// Width over height.
    public var aspectRatio: Double {
        switch self {
        case .horizontal: 16.0 / 9.0
        case .vertical: 9.0 / 16.0
        }
    }

    /// Added to a take's file name, so a tall take is recognisable in Finder.
    /// Horizontal takes keep the plain name they always had.
    public var fileNameSuffix: String? {
        switch self {
        case .horizontal: nil
        case .vertical: "vertical"
        }
    }

    /// Whether `size` already has this format's shape.
    public func hasShape(of size: PixelSize, tolerance: Double = shapeTolerance) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let ratio = Double(size.width) / Double(size.height)
        return abs(ratio / aspectRatio - 1) <= tolerance
    }
}

/// A frame size in whole pixels.
public struct PixelSize: Hashable, Sendable, CustomStringConvertible {

    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The size a movie track shows at: its stored size with its transform
    /// applied, so a turned track reports its upright shape.
    public init(displaying naturalSize: CGSize, transform: CGAffineTransform) {
        let shown = CGRect(origin: .zero, size: naturalSize).applying(transform)
        self.init(width: Int(abs(shown.width).rounded()), height: Int(abs(shown.height).rounded()))
    }

    public var description: String {
        "\(width)x\(height)"
    }
}

/// The part of the camera's frame a take keeps for a format.
///
/// The kept region is centred and as large as the format's shape allows: it
/// keeps the full height and cuts the width when the camera is wider than
/// the format, and keeps the full width and cuts the height when it is
/// taller. Its sides are even pixel counts, because video encoders need
/// them, and never larger than the camera's.
public struct VideoCrop: Equatable, Sendable {

    public let source: PixelSize
    public let format: VideoFormat
    /// The size of the kept region, which is the size of the recorded movie.
    public let output: PixelSize

    public init(source: PixelSize, format: VideoFormat) {
        self.source = source
        self.format = format
        output = Self.keptSize(of: source, aspectRatio: format.aspectRatio)
    }

    /// Whether the camera's frame must be cut. When it already has the
    /// format's shape, the take records the camera's frame as it comes.
    public var needsCrop: Bool {
        !format.hasShape(of: source)
    }

    /// The kept region's top-left corner, in the camera's pixels.
    public var origin: CGPoint {
        CGPoint(x: Double(source.width - output.width) / 2, y: Double(source.height - output.height) / 2)
    }

    /// The kept region as fractions of the camera's frame, origin top left,
    /// for drawing it over a preview of the whole frame.
    public var normalizedRect: CGRect {
        guard source.width > 0, source.height > 0, output.width > 0, output.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let width = Double(source.width)
        let height = Double(source.height)
        return CGRect(
            x: origin.x / width,
            y: origin.y / height,
            width: Double(output.width) / width,
            height: Double(output.height) / height
        )
    }

    /// For cutting a finished movie down to the kept region: the transform
    /// that turns a track's stored frames upright (its `preferredTransform`)
    /// and moves the kept region to the origin of an `output`-sized canvas.
    ///
    /// `source` must be the track's displayed size, from
    /// ``PixelSize/init(displaying:transform:)``.
    public func transform(forTrackWith preferredTransform: CGAffineTransform, naturalSize: CGSize) -> CGAffineTransform {
        let shown = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return preferredTransform.concatenating(
            CGAffineTransform(translationX: -shown.minX - origin.x, y: -shown.minY - origin.y)
        )
    }

    private static func keptSize(of source: PixelSize, aspectRatio: Double) -> PixelSize {
        let maxWidth = evenFloor(source.width)
        let maxHeight = evenFloor(source.height)
        guard maxWidth > 0, maxHeight > 0 else { return PixelSize(width: 0, height: 0) }
        if Double(source.width) / Double(source.height) > aspectRatio {
            let width = nearestEven(Double(maxHeight) * aspectRatio)
            return PixelSize(width: min(maxWidth, max(2, width)), height: maxHeight)
        }
        let height = nearestEven(Double(maxWidth) / aspectRatio)
        return PixelSize(width: maxWidth, height: min(maxHeight, max(2, height)))
    }

    private static func evenFloor(_ value: Int) -> Int {
        max(0, value - value % 2)
    }

    private static func nearestEven(_ value: Double) -> Int {
        Int((value / 2).rounded()) * 2
    }
}
