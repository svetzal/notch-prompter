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

    @Test("grows out of the notch: top edge at the screen's top, centred on the notch")
    func envelopsNotch() {
        let placement = PrompterPlacement(on: macBook, textArea: CGSize(width: 460, height: 164))
        #expect(placement.topInset == 32)
        #expect(placement.frame == CGRect(x: 516, y: 786, width: 480, height: 196))
        #expect(placement.frame.maxY == macBook.frame.maxY)
    }

    @Test("the frame is wider than the text area by an ear on each side")
    func ears() {
        let placement = PrompterPlacement(on: macBook, textArea: CGSize(width: 460, height: 164))
        #expect(placement.frame.width == 460 + 2 * PrompterPlacement.earRadius)
    }

    @Test("the body is never narrower than the notch it covers")
    func bodyCoversNotch() {
        let placement = PrompterPlacement(on: macBook, textArea: CGSize(width: 100, height: 50))
        #expect(placement.frame.width == 185 + 2 * PrompterPlacement.earRadius)
        #expect(placement.frame.height == 82)
    }

    @Test("a display without a notch hangs from the top centre with a small inset")
    func noNotch() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        #expect(display.notch == nil)
        let placement = PrompterPlacement(on: display, textArea: CGSize(width: 400, height: 100))
        #expect(placement.topInset == PrompterPlacement.topInsetWithoutNotch)
        #expect(placement.frame == CGRect(x: 1070, y: 1334, width: 420, height: 106))
        #expect(placement.frame.maxY == display.frame.maxY)
    }

    @Test("uses the display's own origin in a multi-display arrangement")
    func secondaryDisplay() {
        let display = DisplayGeometry(
            frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        let placement = PrompterPlacement(on: display, textArea: CGSize(width: 400, height: 100))
        #expect(placement.frame == CGRect(x: -1170, y: 1174, width: 420, height: 106))
    }

    @Test("shrinks to fit a narrow display, keeping the side margin and the top edge")
    func narrowDisplay() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            safeAreaTop: 0, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero
        )
        let placement = PrompterPlacement(on: display, textArea: CGSize(width: 500, height: 500), margin: 10)
        #expect(placement.frame == CGRect(x: 10, y: 0, width: 280, height: 200))
        #expect(placement.frame.maxY == display.frame.maxY)
    }

    @Test("a notch near the side is followed only as far as the margin allows")
    func centringClamp() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
            safeAreaTop: 30,
            auxiliaryTopLeft: CGRect(x: 0, y: 670, width: 100, height: 30),
            auxiliaryTopRight: CGRect(x: 200, y: 670, width: 800, height: 30)
        )
        let placement = PrompterPlacement(on: display, textArea: CGSize(width: 460, height: 100))
        #expect(placement.frame == CGRect(x: 8, y: 570, width: 480, height: 130))
        #expect(placement.topInset == 30)
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

    @Test("derives line height, text width, and text area size")
    func metrics() {
        let settings = PrompterSettings(fontSize: 30, width: 460, visibleLines: 4)
        #expect(settings.lineHeight == 39)
        #expect(settings.textWidth == 404)
        #expect(settings.textAreaSize == CGSize(width: 460, height: 164))
    }

    @Test("fades a fixed share of a line at each edge, whatever the line count")
    func edgeFade() {
        let four = PrompterSettings(visibleLines: 4)
        #expect(four.topFade == 0.1)
        #expect(four.bottomFade == 0.2)
        let two = PrompterSettings(visibleLines: 2)
        #expect(two.topFade == 0.2)
        #expect(two.bottomFade == 0.4)
        #expect(two.topFade + two.bottomFade < 1)
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
