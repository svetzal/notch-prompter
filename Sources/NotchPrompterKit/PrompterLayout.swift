import Foundation

/// One rendered row of the prompter.
public struct PrompterLine: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case speech
        case note
        case pause(TimeInterval)
    }

    public let text: String
    public let kind: Kind
    /// The index of the ``PrompterBlock`` this line came from.
    public let blockIndex: Int
    /// Whether this is the first line of its block.
    public let startsBlock: Bool

    public init(text: String, kind: Kind, blockIndex: Int, startsBlock: Bool) {
        self.text = text
        self.kind = kind
        self.blockIndex = blockIndex
        self.startsBlock = startsBlock
    }

    public var wordCount: Int {
        Words.count(in: text)
    }
}

/// A document wrapped into fixed-height lines for a given column width.
///
/// Wrapping needs to know how wide text is, which depends on the font. The
/// caller passes a `measure` function, so the layout itself stays pure: tests
/// use a fixed width per character, the app uses the real font.
///
/// Scroll positions are fractional line indices into ``lines``: `2.5` is
/// halfway through the third line.
public struct PrompterLayout: Equatable, Sendable {

    public let lines: [PrompterLine]

    public init(lines: [PrompterLine]) {
        self.lines = lines
    }

    /// Wraps `document` greedily into lines no wider than `width`.
    ///
    /// A word wider than the column gets a line to itself rather than being
    /// split. Pauses take one line each.
    public init(document: PrompterDocument, width: Double, measure: (String) -> Double) {
        var lines: [PrompterLine] = []
        for (blockIndex, block) in document.blocks.enumerated() {
            let wrapped: [(String, PrompterLine.Kind)]
            switch block {
            case .speech(let text):
                wrapped = Self.wrap(text, width: width, measure: measure).map { ($0, .speech) }
            case .note(let text):
                wrapped = Self.wrap(text, width: width, measure: measure).map { ($0, .note) }
            case .pause(let seconds):
                wrapped = [("", .pause(seconds))]
            }
            for (offset, (text, kind)) in wrapped.enumerated() {
                lines.append(PrompterLine(text: text, kind: kind, blockIndex: blockIndex, startsBlock: offset == 0))
            }
        }
        self.init(lines: lines)
    }

    static func wrap(_ text: String, width: Double, measure: (String) -> Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in Words.split(text) {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if current.isEmpty || measure(candidate) <= width {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    /// The position just past the last line.
    public var endPosition: Double {
        Double(lines.count)
    }

    /// Clamps a position into `0...endPosition`.
    public func clamped(_ position: Double) -> Double {
        guard position.isFinite else { return 0 }
        return min(max(position, 0), endPosition)
    }

    /// The line a position falls on, or `nil` past the end.
    public func lineIndex(at position: Double) -> Int? {
        let index = Int(clamped(position).rounded(.down))
        return index < lines.count ? index : nil
    }

    /// The line indices where each block starts, in order.
    public var blockStarts: [Int] {
        lines.indices.filter { lines[$0].startsBlock }
    }

    // MARK: - Paragraph jumps

    /// How far into a paragraph "back" restarts it rather than going to the one before.
    public static let restartThreshold = 0.5

    /// "Back a paragraph", like a music player's previous-track button: if you
    /// are well into a paragraph, return to its start; if you are at the
    /// start, go to the start of the previous one.
    public func previousBlockStart(from position: Double) -> Double {
        let current = clamped(position)
        let starts = blockStarts.map(Double.init)
        guard let containing = starts.last(where: { $0 <= current }) else { return 0 }
        if current - containing > Self.restartThreshold {
            return containing
        }
        return starts.last { $0 < containing } ?? 0
    }

    /// "Forward a paragraph": the start of the next block, or the end.
    public func nextBlockStart(from position: Double) -> Double {
        let current = clamped(position)
        return blockStarts.map(Double.init).first { $0 > current } ?? endPosition
    }

    // MARK: - Relayout

    /// Carries a position across to a new layout of the same document.
    ///
    /// Changing the font size rewraps every paragraph, so a line index means
    /// something different afterwards. The block and the fraction of the way
    /// through it do not change, so that is what survives.
    public func position(_ position: Double, in other: PrompterLayout) -> Double {
        let current = clamped(position)
        guard let lineIndex = lineIndex(at: current) else { return other.endPosition }
        let block = lines[lineIndex].blockIndex
        guard let range = lineRange(ofBlock: block), let otherRange = other.lineRange(ofBlock: block) else {
            return other.clamped(current)
        }
        let fraction = (current - Double(range.lowerBound)) / Double(range.count)
        return other.clamped(Double(otherRange.lowerBound) + fraction * Double(otherRange.count))
    }

    func lineRange(ofBlock block: Int) -> Range<Int>? {
        guard let first = lines.firstIndex(where: { $0.blockIndex == block }) else { return nil }
        let end = lines[first...].firstIndex { $0.blockIndex != block } ?? lines.count
        return first..<end
    }
}
