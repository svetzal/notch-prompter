import CoreGraphics
import Foundation
import Testing
@testable import NotchPrompterKit

@Suite("Video format")
struct VideoFormatTests {

    @Test("names and shapes")
    func names() {
        #expect(VideoFormat.allCases == [.horizontal, .vertical])
        #expect(VideoFormat.horizontal.displayName == "Horizontal")
        #expect(VideoFormat.vertical.displayName == "Vertical")
        #expect(VideoFormat.horizontal.aspectRatio == 16.0 / 9.0)
        #expect(VideoFormat.vertical.aspectRatio == 9.0 / 16.0)
    }

    @Test("stored values read back, and unknown ones are rejected")
    func rawValues() {
        #expect(VideoFormat(rawValue: "vertical") == .vertical)
        #expect(VideoFormat(rawValue: "square") == nil)
    }

    @Test("a size has the format's shape within the tolerance", arguments: [
        (VideoFormat.horizontal, PixelSize(width: 1920, height: 1080), true),
        (.horizontal, PixelSize(width: 1280, height: 720), true),
        (.horizontal, PixelSize(width: 1281, height: 721), true),
        (.horizontal, PixelSize(width: 1080, height: 1920), false),
        (.horizontal, PixelSize(width: 640, height: 480), false),
        (.vertical, PixelSize(width: 608, height: 1080), true),
        (.vertical, PixelSize(width: 406, height: 720), true),
        (.vertical, PixelSize(width: 1080, height: 1920), true),
        (.vertical, PixelSize(width: 1920, height: 1080), false),
        (.vertical, PixelSize(width: 0, height: 0), false)
    ])
    func shape(format: VideoFormat, size: PixelSize, expected: Bool) {
        #expect(format.hasShape(of: size) == expected)
    }
}

@Suite("Video crop")
struct VideoCropTests {

    @Test("keeps the full height and cuts the width for vertical from a landscape camera", arguments: [
        (PixelSize(width: 1920, height: 1080), PixelSize(width: 608, height: 1080)),
        (PixelSize(width: 1280, height: 720), PixelSize(width: 406, height: 720)),
        (PixelSize(width: 3840, height: 2160), PixelSize(width: 1216, height: 2160)),
        (PixelSize(width: 640, height: 480), PixelSize(width: 270, height: 480))
    ])
    func verticalFromLandscape(source: PixelSize, expected: PixelSize) {
        let crop = VideoCrop(source: source, format: .vertical)
        #expect(crop.output == expected)
        #expect(crop.needsCrop)
    }

    @Test("keeps a 16:9 camera whole for horizontal")
    func horizontalFromLandscape() {
        let crop = VideoCrop(source: PixelSize(width: 1920, height: 1080), format: .horizontal)
        #expect(crop.output == PixelSize(width: 1920, height: 1080))
        #expect(!crop.needsCrop)
        #expect(crop.normalizedRect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("cuts a 4:3 camera's height for horizontal")
    func horizontalFromFourThree() {
        let crop = VideoCrop(source: PixelSize(width: 640, height: 480), format: .horizontal)
        #expect(crop.output == PixelSize(width: 640, height: 360))
        #expect(crop.needsCrop)
    }

    @Test("an upright iPhone stays whole for vertical and loses height for horizontal")
    func portraitSource() {
        let upright = PixelSize(width: 1080, height: 1920)
        let vertical = VideoCrop(source: upright, format: .vertical)
        #expect(vertical.output == upright)
        #expect(!vertical.needsCrop)

        let horizontal = VideoCrop(source: upright, format: .horizontal)
        #expect(horizontal.output == PixelSize(width: 1080, height: 608))
        #expect(horizontal.needsCrop)
    }

    @Test("odd sources give even sizes that never exceed the source", arguments: [
        (PixelSize(width: 1281, height: 721), VideoFormat.horizontal),
        (PixelSize(width: 1281, height: 721), .vertical),
        (PixelSize(width: 1919, height: 1079), .vertical),
        (PixelSize(width: 1079, height: 1919), .horizontal),
        (PixelSize(width: 1079, height: 1919), .vertical),
        (PixelSize(width: 3, height: 3), .vertical)
    ])
    func oddSizes(source: PixelSize, format: VideoFormat) {
        let output = VideoCrop(source: source, format: format).output
        #expect(output.width.isMultiple(of: 2))
        #expect(output.height.isMultiple(of: 2))
        #expect(output.width <= source.width)
        #expect(output.height <= source.height)
        #expect(output.width > 0 && output.height > 0)
    }

    @Test("an empty source gives an empty crop")
    func emptySource() {
        let crop = VideoCrop(source: PixelSize(width: 0, height: 0), format: .vertical)
        #expect(crop.output == PixelSize(width: 0, height: 0))
        #expect(crop.normalizedRect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("the kept region is centred")
    func centred() {
        let crop = VideoCrop(source: PixelSize(width: 1920, height: 1080), format: .vertical)
        #expect(crop.origin == CGPoint(x: 656, y: 0))
        let rect = crop.normalizedRect
        #expect(abs(rect.midX - 0.5) < 1e-9)
        #expect(abs(rect.midY - 0.5) < 1e-9)
        #expect(abs(rect.width - 608.0 / 1920.0) < 1e-9)
        #expect(rect.height == 1)
    }

    @Test("the kept region of a horizontal crop from an upright iPhone is a centred band")
    func centredBand() {
        let crop = VideoCrop(source: PixelSize(width: 1080, height: 1920), format: .horizontal)
        #expect(crop.origin == CGPoint(x: 0, y: 656))
        #expect(crop.normalizedRect.width == 1)
        #expect(abs(crop.normalizedRect.minY - 656.0 / 1920.0) < 1e-9)
    }
}

@Suite("Finished movie shape")
struct MovieShapeTests {

    /// How an upright iPhone movie is usually stored: landscape pixels turned a quarter.
    private let quarterTurn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)

    @Test("the displayed size applies the track's transform")
    func displayedSize() {
        let natural = CGSize(width: 1920, height: 1080)
        #expect(PixelSize(displaying: natural, transform: .identity) == PixelSize(width: 1920, height: 1080))
        #expect(PixelSize(displaying: natural, transform: quarterTurn) == PixelSize(width: 1080, height: 1920))
    }

    @Test("re-cropping a plain track moves the kept region to the origin")
    func plainTrack() {
        let crop = VideoCrop(source: PixelSize(width: 1920, height: 1080), format: .vertical)
        let transform = crop.transform(forTrackWith: .identity, naturalSize: CGSize(width: 1920, height: 1080))
        #expect(transform == CGAffineTransform(translationX: -656, y: 0))
    }

    @Test("re-cropping a turned track keeps its turn and centres the kept region", arguments: [
        CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
        CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
    ])
    func turnedTrack(preferred: CGAffineTransform) {
        let natural = CGSize(width: 1920, height: 1080)
        let crop = VideoCrop(source: PixelSize(displaying: natural, transform: preferred), format: .horizontal)
        #expect(crop.output == PixelSize(width: 1080, height: 608))
        let transform = crop.transform(forTrackWith: preferred, naturalSize: natural)
        let centre = CGPoint(x: 960, y: 540).applying(transform)
        #expect(abs(centre.x - 540) < 1e-9)
        #expect(abs(centre.y - 304) < 1e-9)
    }
}
