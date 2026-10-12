import CoreGraphics
import Testing
@testable import NotchPrompterKit

@Suite("Prompter placement")
struct PrompterPlacementTests {

    /// A 14-inch MacBook Pro at its default scaling: 1512 x 982 points, a
    /// 32-point safe area, and a notch about 185 points wide.
    let macBook = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32)
    )

    @Test("finds the notch between the auxiliary areas")
    func notch() {
        #expect(macBook.notch == CGRect(x: 663, y: 950, width: 185, height: 32))
    }

    @Test("an uneven notch is centred on its own middle, not the screen's")
    func unevenNotch() throws {
        let notch = try #require(macBook.notch)
        #expect(notch.midX == 755.5)
    }

    @Test("sits directly under the notch, centred on it")
    func underNotch() {
        let frame = PrompterPlacement.frame(on: macBook, size: CGSize(width: 460, height: 164))
        #expect(frame == CGRect(x: 526, y: 786, width: 460, height: 164))
    }

    @Test("a display without a notch gets the top centre")
    func noNotch() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        #expect(display.notch == nil)
        let frame = PrompterPlacement.frame(on: display, size: CGSize(width: 400, height: 100))
        #expect(frame == CGRect(x: 1080, y: 1340, width: 400, height: 100))
    }

    @Test("uses the display's own origin in a multi-display arrangement")
    func secondaryDisplay() {
        let display = DisplayGeometry(
            frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        let frame = PrompterPlacement.frame(on: display, size: CGSize(width: 400, height: 100))
        #expect(frame == CGRect(x: -1160, y: 1180, width: 400, height: 100))
    }

    @Test("shrinks to fit a narrow display, keeping the margin")
    func narrowDisplay() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        let frame = PrompterPlacement.frame(on: display, size: CGSize(width: 500, height: 500), margin: 10)
        #expect(frame == CGRect(x: 10, y: 0, width: 280, height: 200))
    }

    @Test("a safe area without auxiliary areas is not a notch")
    func safeAreaAlone() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            safeAreaTop: 24, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        #expect(display.notch == nil)
    }
}

@Suite("Prompter settings")
struct PrompterSettingsTests {

    @Test("derives line height, text width, and panel size")
    func metrics() {
        let settings = PrompterSettings(fontSize: 30, width: 460, visibleLines: 4)
        #expect(settings.lineHeight == 39)
        #expect(settings.textWidth == 428)
        #expect(settings.panelSize == CGSize(width: 460, height: 172))
    }

    @Test("clamps on creation and on every change")
    func clamping() {
        var settings = PrompterSettings(wordsPerMinute: 5, fontSize: 500, width: .nan, visibleLines: 0, countdownSeconds: 99)
        #expect(settings.wordsPerMinute == PrompterSettings.speedRange.lowerBound)
        #expect(settings.fontSize == PrompterSettings.fontSizeRange.upperBound)
        #expect(settings.width == PrompterSettings.widthRange.lowerBound)
        #expect(settings.visibleLines == PrompterSettings.visibleLinesRange.lowerBound)
        #expect(settings.countdownSeconds == PrompterSettings.countdownRange.upperBound)
        settings.wordsPerMinute = 1_000
        #expect(settings.wordsPerMinute == PrompterSettings.speedRange.upperBound)
    }

    @Test("steps speed and text size within limits")
    func steps() {
        var settings = PrompterSettings(wordsPerMinute: 140, fontSize: 30)
        settings.faster()
        settings.largerText()
        #expect(settings.wordsPerMinute == 150)
        #expect(settings.fontSize == 32)
        settings.wordsPerMinute = PrompterSettings.speedRange.lowerBound
        settings.slower()
        #expect(settings.wordsPerMinute == PrompterSettings.speedRange.lowerBound)
    }
}

@Suite("Preferred selection")
struct PreferredSelectionTests {

    @Test("keeps the person's choice while it is available")
    func keepsChoice() {
        #expect(PreferredSelection.resolve(preferred: "b", available: ["a", "b"], fallbacks: ["a"]) == "b")
    }

    @Test("falls back in order when the choice is gone")
    func fallsBack() {
        #expect(PreferredSelection.resolve(preferred: "x", available: ["a", "b", "c"], fallbacks: [nil, "c", "b"]) == "c")
        #expect(PreferredSelection.resolve(preferred: "x", available: ["a", "b"]) == "a")
        #expect(PreferredSelection.resolve(preferred: "x", available: [String]()) == nil)
    }
}
