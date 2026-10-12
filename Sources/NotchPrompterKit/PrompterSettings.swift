import CoreGraphics
import Foundation

/// The presenter's prompter preferences, with their limits and step sizes.
///
/// Every setter clamps, so a stored preference or a held-down key can never
/// push the prompter into an unreadable state.
public struct PrompterSettings: Equatable, Sendable {

    public static let speedRange: ClosedRange<Double> = 60...300
    public static let speedStep = 10.0
    public static let fontSizeRange: ClosedRange<Double> = 16...64
    public static let fontSizeStep = 2.0
    public static let widthRange: ClosedRange<Double> = 280...900
    public static let visibleLinesRange: ClosedRange<Int> = 2...8
    public static let countdownRange: ClosedRange<Int> = 0...10

    /// Line height as a multiple of the font size.
    public static let lineSpacing = 1.3
    /// Space inside the panel, left and right of the text column.
    public static let horizontalPadding = 16.0
    /// Space inside the panel, above and below the lines.
    public static let verticalPadding = 8.0

    public var wordsPerMinute: Double { didSet { wordsPerMinute = Self.clamp(wordsPerMinute, to: Self.speedRange) } }
    public var fontSize: Double { didSet { fontSize = Self.clamp(fontSize, to: Self.fontSizeRange) } }
    public var width: Double { didSet { width = Self.clamp(width, to: Self.widthRange) } }
    public var visibleLines: Int { didSet { visibleLines = Self.clamp(visibleLines, to: Self.visibleLinesRange) } }
    public var countdownSeconds: Int {
        didSet { countdownSeconds = Self.clamp(countdownSeconds, to: Self.countdownRange) }
    }

    public init(
        wordsPerMinute: Double = 140,
        fontSize: Double = 30,
        width: Double = 460,
        visibleLines: Int = 4,
        countdownSeconds: Int = 3
    ) {
        self.wordsPerMinute = Self.clamp(wordsPerMinute, to: Self.speedRange)
        self.fontSize = Self.clamp(fontSize, to: Self.fontSizeRange)
        self.width = Self.clamp(width, to: Self.widthRange)
        self.visibleLines = Self.clamp(visibleLines, to: Self.visibleLinesRange)
        self.countdownSeconds = Self.clamp(countdownSeconds, to: Self.countdownRange)
    }

    public var lineHeight: Double {
        (fontSize * Self.lineSpacing).rounded()
    }

    /// The width available to text, which is what layout wraps to.
    public var textWidth: Double {
        width - 2 * Self.horizontalPadding
    }

    public var panelSize: CGSize {
        CGSize(width: width, height: Double(visibleLines) * lineHeight + 2 * Self.verticalPadding)
    }

    public mutating func faster() { wordsPerMinute += Self.speedStep }
    public mutating func slower() { wordsPerMinute -= Self.speedStep }
    public mutating func largerText() { fontSize += Self.fontSizeStep }
    public mutating func smallerText() { fontSize -= Self.fontSizeStep }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
