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

/// Picks the camera format for a take's shape, so the take records the
/// camera's whole frame instead of a cut from its centre.
///
/// On macOS the app cannot know which format the `.high` session preset
/// will choose, and a format the app set earlier can still be in place, so
/// the app chooses the format itself for both shapes. The MacBook Pro camera
/// lists 1920x1080 and 1080x1920, so each shape records the full frame. An
/// iPhone as a Continuity Camera lists only landscape formats, so Vertical
/// keeps the cut from its centre. A camera with neither shape (4:3 only, for
/// example) keeps the cut for both, from the format the preset chooses.
public enum NativeFormat {

    /// The slowest frame rate a native format may have.
    public static let minimumFrameRate = 30.0

    /// Frame rates are reported as floating-point values, so one listed as
    /// 30 can read a little under it.
    static let frameRateTolerance = 0.01

    /// The index in `formats` of the format to put the camera in for
    /// `videoFormat`, or `nil` when the camera has no such format and the
    /// take is cut from the format the session preset chooses.
    ///
    /// A format qualifies when it has the shape (within
    /// ``VideoFormat/shapeTolerance``), runs at 30 frames per second or
    /// more, and supports every effect in ``effectsBaseline(of:)``, so
    /// neither shape gives up an effect the camera can do. Of those, the
    /// most pixels wins, then the higher frame rate, then the first listed.
    public static func index(for videoFormat: VideoFormat, in formats: [CameraFormat]) -> Int? {
        let effects = effectsBaseline(of: formats)
        let candidates = formats.indices.filter { index in
            let format = formats[index]
            return videoFormat.hasShape(of: format.size)
                && format.maxFrameRate >= minimumFrameRate - frameRateTolerance
                && effects.isSubset(of: format.supportedEffects)
        }
        return candidates.max { lhs, rhs in
            rank(formats[lhs], at: lhs) < rank(formats[rhs], at: rhs)
        }
    }

    /// The effects the camera can do at its best: those of its most capable
    /// format, the one supporting the most effects. A tie goes to the higher
    /// resolution, then the higher frame rate, then the first listed.
    public static func effectsBaseline(of formats: [CameraFormat]) -> Set<VideoEffect> {
        let mostCapable = formats.indices.max { lhs, rhs in
            let lhsCount = formats[lhs].supportedEffects.count
            let rhsCount = formats[rhs].supportedEffects.count
            guard lhsCount == rhsCount else { return lhsCount < rhsCount }
            return rank(formats[lhs], at: lhs) < rank(formats[rhs], at: rhs)
        }
        return mostCapable.map { formats[$0].supportedEffects } ?? []
    }

    /// Higher ranks better. The negated index makes the earlier of two
    /// otherwise equal formats rank higher.
    private static func rank(_ format: CameraFormat, at index: Int) -> (Int, Double, Int) {
        (format.size.width * format.size.height, format.maxFrameRate, -index)
    }
}
