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

    @Test("picks the MacBook camera's 1080x1920 format for vertical")
    func macBookVertical() {
        let index = NativeFormat.index(for: .vertical, in: Self.macBookCamera, keeping: Self.everyEffect)
        #expect(index.map { Self.macBookCamera[$0].size } == PixelSize(width: 1080, height: 1920))
    }

    @Test("finds none on an iPhone, which keeps the crop path")
    func iPhoneVertical() {
        #expect(NativeFormat.index(for: .vertical, in: Self.iPhoneCamera, keeping: Self.everyEffect) == nil)
    }

    @Test("horizontal always uses the session preset")
    func horizontal() {
        #expect(NativeFormat.index(for: .horizontal, in: Self.macBookCamera, keeping: Self.everyEffect) == nil)
    }

    @Test("rejects portrait formats that are not 9:16")
    func shape() {
        let formats = [Self.format(1328, 1760), Self.format(1552, 1552), Self.format(480, 640)]
        #expect(NativeFormat.index(for: .vertical, in: formats, keeping: []) == nil)
    }

    @Test("rejects a format slower than 30 frames per second")
    func frameRate() {
        let formats = [Self.format(1080, 1920, fps: 24), Self.format(720, 1280)]
        let index = NativeFormat.index(for: .vertical, in: formats, keeping: [])
        #expect(index.map { formats[$0].size } == PixelSize(width: 720, height: 1280))
    }

    @Test("accepts a frame rate reported a hair under 30")
    func frameRateRounding() {
        let formats = [Self.format(1080, 1920, fps: 29.999)]
        #expect(NativeFormat.index(for: .vertical, in: formats, keeping: []) == 0)
    }

    @Test("rejects a format that drops an effect the current format supports")
    func missingEffect() {
        let formats = [
            Self.format(1080, 1920, effects: Self.everyEffect.subtracting([.edgeLight])),
            Self.format(720, 1280)
        ]
        let index = NativeFormat.index(for: .vertical, in: formats, keeping: Self.everyEffect)
        #expect(index.map { formats[$0].size } == PixelSize(width: 720, height: 1280))
    }

    @Test("ignores effects the current format does not support either")
    func effectsNotInUse() {
        let formats = [Self.format(1080, 1920, effects: [.centerStage])]
        #expect(NativeFormat.index(for: .vertical, in: formats, keeping: [.centerStage]) == 0)
    }

    @Test("the highest resolution wins")
    func highestResolution() {
        let formats = [Self.format(720, 1280), Self.format(2160, 3840), Self.format(1080, 1920)]
        #expect(NativeFormat.index(for: .vertical, in: formats, keeping: []) == 1)
    }

    @Test("a tie on resolution goes to the faster format, then to the first listed")
    func ties() {
        let faster = [Self.format(1080, 1920), Self.format(1080, 1920, fps: 60)]
        #expect(NativeFormat.index(for: .vertical, in: faster, keeping: []) == 1)
        let same = [Self.format(1080, 1920), Self.format(1080, 1920)]
        #expect(NativeFormat.index(for: .vertical, in: same, keeping: []) == 0)
    }

    @Test("a camera with no formats has no native format")
    func empty() {
        #expect(NativeFormat.index(for: .vertical, in: [], keeping: []) == nil)
    }
}
