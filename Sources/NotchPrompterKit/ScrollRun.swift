import Foundation

/// How long each prompter line stays on the reading line.
///
/// Speech lines take as long as their words take at the reading speed. Note
/// lines glide past at ``noteLineWords`` words' worth, since nobody reads
/// them aloud. Pause lines hold for their cue's seconds, whatever the speed.
public struct ScrollTimeline: Equatable, Sendable {

    /// The reading cost of one note line, in words.
    public static let noteLineWords = 2.0

    struct Cost: Equatable, Sendable {
        let words: Double
        let hold: TimeInterval
    }

    let costs: [Cost]

    public init(layout: PrompterLayout) {
        costs = layout.lines.map { line in
            switch line.kind {
            case .speech: Cost(words: Double(max(1, line.wordCount)), hold: 0)
            case .note: Cost(words: Self.noteLineWords, hold: 0)
            case .pause(let seconds): Cost(words: 0, hold: seconds)
            }
        }
    }

    public var endPosition: Double {
        Double(costs.count)
    }

    /// Seconds line `index` spends on the reading line at `wordsPerMinute`.
    public func duration(ofLine index: Int, wordsPerMinute: Double) -> TimeInterval {
        let cost = costs[index]
        return cost.words * 60 / wordsPerMinute + cost.hold
    }

    /// Where the scroll is after reading for `elapsed` seconds from `position`.
    ///
    /// This is the heart of the scroll engine. It walks line by line, so a
    /// pause line holds for its full time no matter where it falls, and
    /// stops at ``endPosition``.
    public func advance(from position: Double, by elapsed: TimeInterval, wordsPerMinute: Double) -> Double {
        guard wordsPerMinute > 0, elapsed > 0 else { return position }
        var current = min(max(position, 0), endPosition)
        var remaining = elapsed
        while remaining > 0, current < endPosition {
            let line = Int(current.rounded(.down))
            let lineDuration = duration(ofLine: line, wordsPerMinute: wordsPerMinute)
            let leftInLine = (Double(line + 1) - current) * lineDuration
            if lineDuration <= 0 || remaining >= leftInLine {
                remaining -= max(leftInLine, 0)
                current = Double(line + 1)
            } else {
                current += remaining / lineDuration
                remaining = 0
            }
        }
        return current
    }

    /// Seconds left to read from `position` to the end.
    public func remainingTime(from position: Double, wordsPerMinute: Double) -> TimeInterval {
        guard wordsPerMinute > 0 else { return .infinity }
        var current = min(max(position, 0), endPosition)
        var total: TimeInterval = 0
        while current < endPosition {
            let line = Int(current.rounded(.down))
            total += (Double(line + 1) - current) * duration(ofLine: line, wordsPerMinute: wordsPerMinute)
            current = Double(line + 1)
        }
        return total
    }
}

/// The scroll state of one prompter run.
///
/// Position is never stored as it changes. The run keeps an anchor (a
/// position and, while playing, the moment it was taken) and computes the
/// current position from the clock. Every control that changes the scroll
/// (pause, speed, nudge, jump) re-anchors at "now". That makes position a
/// pure function of elapsed time, speed, pauses, and nudges, and lets the
/// view redraw at any frame rate without drift.
public struct ScrollRun: Equatable, Sendable {

    public private(set) var layout: PrompterLayout
    public private(set) var timeline: ScrollTimeline
    public private(set) var wordsPerMinute: Double
    private var anchorPosition: Double
    private var anchorTime: Date?

    public init(layout: PrompterLayout, wordsPerMinute: Double, position: Double = 0) {
        self.layout = layout
        timeline = ScrollTimeline(layout: layout)
        self.wordsPerMinute = wordsPerMinute
        anchorPosition = layout.clamped(position)
    }

    public var isPlaying: Bool {
        anchorTime != nil
    }

    public func position(at now: Date) -> Double {
        guard let anchorTime else { return anchorPosition }
        return timeline.advance(from: anchorPosition, by: now.timeIntervalSince(anchorTime), wordsPerMinute: wordsPerMinute)
    }

    public func isFinished(at now: Date) -> Bool {
        position(at: now) >= layout.endPosition
    }

    public mutating func play(at now: Date) {
        guard !isPlaying else { return }
        anchorTime = now
    }

    public mutating func pause(at now: Date) {
        guard isPlaying else { return }
        anchorPosition = position(at: now)
        anchorTime = nil
    }

    public mutating func togglePlayback(at now: Date) {
        if isPlaying {
            pause(at: now)
        } else {
            play(at: now)
        }
    }

    public mutating func setSpeed(_ wordsPerMinute: Double, at now: Date) {
        reanchor(at: now, to: position(at: now))
        self.wordsPerMinute = wordsPerMinute
    }

    /// Moves to a position, keeping the play state.
    public mutating func seek(to position: Double, at now: Date) {
        reanchor(at: now, to: layout.clamped(position))
    }

    /// Moves by a number of lines, forward or back.
    public mutating func nudge(byLines lines: Double, at now: Date) {
        seek(to: position(at: now) + lines, at: now)
    }

    public mutating func jumpToPreviousBlock(at now: Date) {
        seek(to: layout.previousBlockStart(from: position(at: now)), at: now)
    }

    public mutating func jumpToNextBlock(at now: Date) {
        seek(to: layout.nextBlockStart(from: position(at: now)), at: now)
    }

    /// Swaps in a new layout of the same document, keeping the reader's place.
    public mutating func relayout(_ newLayout: PrompterLayout, at now: Date) {
        let carried = layout.position(position(at: now), in: newLayout)
        layout = newLayout
        timeline = ScrollTimeline(layout: newLayout)
        reanchor(at: now, to: carried)
    }

    private mutating func reanchor(at now: Date, to position: Double) {
        anchorPosition = position
        if isPlaying {
            anchorTime = now
        }
    }
}
