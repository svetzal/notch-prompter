import Testing
@testable import NotchPrompterKit

@Suite("Native camera format")
struct NativeFormatTests {

    static let everyEffect: Set<VideoEffect> = [.portrait, .studioLight, .backgroundReplacement, .edgeLight, .centerStage]

    static func format(
        _ width: Int,
        _ height: Int,
        fps: Double = 30,
        effects: Set<VideoEffect> = everyEffect
    ) -> CameraFormat {
        CameraFormat(size: PixelSize(width: width, height: height), maxFrameRate: fps, supportedEffects: effects)
    }

    /// The MacBook Pro Camera's formats, as listed on the development Mac.
    static let macBookCamera = [
        format(640, 480), format(1280, 720), format(1760, 1328), format(1328, 1760),
        format(1552, 1552), format(1920, 1080), format(1080, 1920)
    ]

    /// An iPhone as a Continuity Camera lists landscape formats only.
    static let iPhoneCamera = [
        format(640, 480), format(640, 480, fps: 60), format(1280, 720), format(1280, 720, fps: 60),
        format(1920, 1080), format(1920, 1080, fps: 60), format(1920, 1440), format(1920, 1440, fps: 60)
    ]

    func size(for videoFormat: VideoFormat, in formats: [CameraFormat]) -> PixelSize? {
        NativeFormat.index(for: videoFormat, in: formats).map { formats[$0].size }
    }

    @Test("the MacBook camera has a native format for both shapes")
    func macBook() {
        #expect(size(for: .horizontal, in: Self.macBookCamera) == PixelSize(width: 1920, height: 1080))
        #expect(size(for: .vertical, in: Self.macBookCamera) == PixelSize(width: 1080, height: 1920))
    }

    @Test("an iPhone has a native horizontal format and keeps the crop for vertical")
    func iPhone() {
        let horizontal = NativeFormat.index(for: .horizontal, in: Self.iPhoneCamera)
        #expect(horizontal.map { Self.iPhoneCamera[$0].size } == PixelSize(width: 1920, height: 1080))
        #expect(horizontal.map { Self.iPhoneCamera[$0].maxFrameRate } == 60)
        #expect(NativeFormat.index(for: .vertical, in: Self.iPhoneCamera) == nil)
    }

    @Test("a 4:3-only camera keeps the crop for both shapes")
    func fourThreeOnly() {
        let formats = [Self.format(640, 480), Self.format(1280, 960), Self.format(1920, 1440)]
        #expect(NativeFormat.index(for: .horizontal, in: formats) == nil)
        #expect(NativeFormat.index(for: .vertical, in: formats) == nil)
    }

    @Test("rejects formats without the shape")
    func shape() {
        let formats = [Self.format(1328, 1760), Self.format(1552, 1552), Self.format(480, 640)]
        #expect(NativeFormat.index(for: .vertical, in: formats) == nil)
        #expect(NativeFormat.index(for: .horizontal, in: formats) == nil)
    }

    @Test("rejects a format slower than 30 frames per second", arguments: VideoFormat.allCases)
    func frameRate(videoFormat: VideoFormat) {
        let formats = videoFormat == .vertical
            ? [Self.format(1080, 1920, fps: 24), Self.format(720, 1280)]
            : [Self.format(1920, 1080, fps: 24), Self.format(1280, 720)]
        #expect(NativeFormat.index(for: videoFormat, in: formats) == 1)
    }

    @Test("accepts a frame rate reported a hair under 30")
    func frameRateRounding() {
        #expect(NativeFormat.index(for: .vertical, in: [Self.format(1080, 1920, fps: 29.999)]) == 0)
    }

    @Test("rejects a format that drops an effect the camera can do", arguments: VideoFormat.allCases)
    func missingEffect(videoFormat: VideoFormat) {
        let lacking = Self.everyEffect.subtracting([.edgeLight])
        let formats = videoFormat == .vertical
            ? [Self.format(1080, 1920, effects: lacking), Self.format(720, 1280)]
            : [Self.format(1920, 1080, effects: lacking), Self.format(1280, 720)]
        #expect(NativeFormat.index(for: videoFormat, in: formats) == 1)
    }

    @Test("needs only the effects the camera can do somewhere")
    func effectsNoFormatSupports() {
        let formats = [Self.format(1080, 1920, effects: [.centerStage]), Self.format(1920, 1080, effects: [.centerStage])]
        #expect(NativeFormat.index(for: .vertical, in: formats) == 0)
        #expect(NativeFormat.index(for: .horizontal, in: formats) == 1)
    }

    @Test("the highest resolution wins")
    func highestResolution() {
        let formats = [Self.format(720, 1280), Self.format(2160, 3840), Self.format(1080, 1920)]
        #expect(NativeFormat.index(for: .vertical, in: formats) == 1)
    }

    @Test("a tie on resolution goes to the faster format, then to the first listed")
    func ties() {
        let faster = [Self.format(1920, 1080), Self.format(1920, 1080, fps: 60)]
        #expect(NativeFormat.index(for: .horizontal, in: faster) == 1)
        let same = [Self.format(1080, 1920), Self.format(1080, 1920)]
        #expect(NativeFormat.index(for: .vertical, in: same) == 0)
    }

    @Test("a camera with no formats has no native format and no effects")
    func empty() {
        #expect(NativeFormat.index(for: .vertical, in: []) == nil)
        #expect(NativeFormat.effectsBaseline(of: []).isEmpty)
    }

    @Test("the baseline is the effects of the format that supports the most")
    func baselineMostEffects() {
        let formats = [
            Self.format(1920, 1080, effects: [.centerStage]),
            Self.format(1280, 720, effects: [.centerStage, .portrait, .studioLight]),
            Self.format(640, 480, effects: [.portrait])
        ]
        #expect(NativeFormat.effectsBaseline(of: formats) == [.centerStage, .portrait, .studioLight])
    }

    @Test("a tie on effect count goes to the higher resolution")
    func baselineTie() {
        let formats = [
            Self.format(1280, 720, effects: [.portrait, .centerStage]),
            Self.format(1920, 1080, effects: [.studioLight, .edgeLight]),
            Self.format(1080, 1920, effects: [.portrait, .centerStage])
        ]
        #expect(NativeFormat.effectsBaseline(of: formats) == [.studioLight, .edgeLight])
        #expect(NativeFormat.index(for: .horizontal, in: formats) == 1)
        #expect(NativeFormat.index(for: .vertical, in: formats) == nil)
    }

    @Test("a lesser format the preset might have chosen does not lower the baseline")
    func baselineIgnoresCurrentFormat() {
        let formats = [
            Self.format(1920, 1080, effects: [.centerStage]),
            Self.format(1080, 1920),
            Self.format(1920, 1080, fps: 30)
        ]
        #expect(NativeFormat.effectsBaseline(of: formats) == Self.everyEffect)
        #expect(NativeFormat.index(for: .horizontal, in: formats) == 2)
    }
}
