/// One of a camera's formats, as plain values the Kit can decide on.
public struct CameraFormat: Equatable, Sendable {

    public let size: PixelSize
    /// The highest frame rate any of the format's frame rate ranges allows.
    public let maxFrameRate: Double
    /// The system video effects the format can render.
    public let supportedEffects: Set<VideoEffect>

    public init(size: PixelSize, maxFrameRate: Double, supportedEffects: Set<VideoEffect>) {
        self.size = size
        self.maxFrameRate = maxFrameRate
        self.supportedEffects = supportedEffects
    }
}

/// Picks a camera format that already has a take's shape, so the take
/// records the camera's whole frame instead of a cut from its centre.
///
/// Some cameras list a native portrait format. The MacBook Pro camera lists
/// 1080x1920, so a vertical take from it keeps all 1080x1920 pixels instead
/// of the 608x1080 cut from its 1920x1080 frame. An iPhone as a Continuity
/// Camera lists only landscape formats, so it keeps the cut.
public enum NativeFormat {

    /// The slowest frame rate a native format may have.
    public static let minimumFrameRate = 30.0

    /// Frame rates are reported as floating-point values, so one listed as
    /// 30 can read a little under it.
    static let frameRateTolerance = 0.01

    /// The index in `formats` of the format to switch the camera to for
    /// `videoFormat`, or `nil` to use the session preset's format.
    ///
    /// Horizontal always returns `nil`: the session preset already picks a
    /// 16:9 format. For vertical, a format qualifies when it has the 9:16
    /// shape (within ``VideoFormat/shapeTolerance``), runs at 30 frames per
    /// second or more, and supports every effect in `effects`, which is what
    /// the camera's current format supports, so switching never takes away
    /// an effect. Of those, the most pixels wins, then the higher frame rate,
    /// then the first listed.
    public static func index(
        for videoFormat: VideoFormat,
        in formats: [CameraFormat],
        keeping effects: Set<VideoEffect>
    ) -> Int? {
        guard videoFormat == .vertical else { return nil }
        let candidates = formats.indices.filter { index in
            let format = formats[index]
            return videoFormat.hasShape(of: format.size)
                && format.maxFrameRate >= minimumFrameRate - frameRateTolerance
                && effects.isSubset(of: format.supportedEffects)
        }
        return candidates.max { lhs, rhs in
            // The negated index makes the earlier of two equal formats rank higher.
            rank(formats[lhs], at: lhs) < rank(formats[rhs], at: rhs)
        }
    }

    private static func rank(_ format: CameraFormat, at index: Int) -> (Int, Double, Int) {
        (format.size.width * format.size.height, format.maxFrameRate, -index)
    }
}
