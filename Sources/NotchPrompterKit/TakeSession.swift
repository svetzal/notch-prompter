import Foundation

/// The prompter and recording lifecycle, as a pure state machine.
///
/// The app feeds it events (a key press, the countdown ending, the movie
/// file closing) with the current time, and gets back ``Command``s to carry
/// out: show or hide the panel, start or stop recording, schedule the end of
/// the countdown. Nothing here touches a window or a camera, so every rule
/// about what happens when is testable.
///
/// The phases run:
///
/// ```
/// hidden ──show──▶ ready ──begin──▶ countingDown ──▶ live ──stop──▶ ready ──stop──▶ hidden
///                                                     │ (recording)
///                                                     └──stop──▶ finishing ──file closed──▶ ready
/// ```
public struct TakeSession: Equatable, Sendable {

    public enum Mode: Equatable, Sendable {
        /// Prompter only: practice without recording.
        case rehearsal
        /// Prompter and recording together.
        case recording
    }

    public enum Phase: Equatable, Sendable {
        case hidden
        case ready
        case countingDown(Mode, endsAt: Date)
        case live(Mode, startedAt: Date)
        /// Recording has been told to stop; the movie file is still closing.
        case finishing
    }

    public enum Command: Equatable, Sendable {
        case showPrompter
        case hidePrompter
        /// Call ``TakeSession/countdownDidEnd(scheduledFor:at:)`` at this moment.
        case scheduleCountdownEnd(Date)
        case startRecording
        case stopRecording
    }

    public private(set) var phase: Phase = .hidden
    public private(set) var scroll: ScrollRun
    /// Seconds of countdown before each run.
    public var countdown: TimeInterval

    public init(layout: PrompterLayout, wordsPerMinute: Double, countdown: TimeInterval) {
        scroll = ScrollRun(layout: layout, wordsPerMinute: wordsPerMinute)
        self.countdown = countdown
    }

    // MARK: - Reading the state

    public var isPrompterVisible: Bool {
        phase != .hidden
    }

    /// Whether a recording is under way or closing, which locks device changes.
    public var isRecording: Bool {
        switch phase {
        case .live(.recording, _), .finishing: true
        default: false
        }
    }

    /// Whether a take can start now.
    public var canBegin: Bool {
        phase == .hidden || phase == .ready
    }

    /// Whole seconds left in the countdown, never showing zero.
    public func countdownRemaining(at now: Date) -> Int? {
        guard case .countingDown(_, let endsAt) = phase else { return nil }
        return max(1, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    /// Time since the run went live.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard case .live(_, let startedAt) = phase else { return nil }
        return max(0, now.timeIntervalSince(startedAt))
    }

    public func position(at now: Date) -> Double {
        scroll.position(at: now)
    }

    // MARK: - Lifecycle events

    public mutating func showPrompter() -> [Command] {
        guard phase == .hidden else { return [] }
        phase = .ready
        return [.showPrompter]
    }

    /// Starts a rehearsal or a recorded take: the countdown, then the scroll.
    ///
    /// A run that would start at the end of the script starts from the top.
    public mutating func begin(_ mode: Mode, at now: Date) -> [Command] {
        guard canBegin else { return [] }
        var commands: [Command] = phase == .hidden ? [.showPrompter] : []
        scroll.pause(at: now)
        if scroll.isFinished(at: now) {
            scroll.seek(to: 0, at: now)
        }
        let endsAt = now.addingTimeInterval(max(0, countdown))
        phase = .countingDown(mode, endsAt: endsAt)
        if countdown > 0 {
            commands.append(.scheduleCountdownEnd(endsAt))
        } else {
            commands += countdownDidEnd(scheduledFor: endsAt, at: now)
        }
        return commands
    }

    /// The countdown scheduled for `endsAt` has run out.
    ///
    /// A stale timer, from a countdown that was cancelled and replaced, does
    /// nothing because its `endsAt` no longer matches.
    public mutating func countdownDidEnd(scheduledFor endsAt: Date, at now: Date) -> [Command] {
        guard case .countingDown(let mode, let expected) = phase, expected == endsAt else { return [] }
        phase = .live(mode, startedAt: now)
        scroll.play(at: now)
        return mode == .recording ? [.startRecording] : []
    }

    /// Esc: stop whatever is running, or hide the prompter if nothing is.
    public mutating func stop(at now: Date) -> [Command] {
        switch phase {
        case .hidden, .finishing:
            return []
        case .ready:
            phase = .hidden
            return [.hidePrompter]
        case .countingDown:
            phase = .ready
            return []
        case .live(.rehearsal, _):
            scroll.pause(at: now)
            phase = .ready
            return []
        case .live(.recording, _):
            scroll.pause(at: now)
            phase = .finishing
            return [.stopRecording]
        }
    }

    /// The movie file has closed, whether because we stopped it or because
    /// recording failed on its own (a full disk, a camera unplugged).
    public mutating func recordingDidEnd(at now: Date) {
        switch phase {
        case .finishing, .live(.recording, _):
            scroll.pause(at: now)
            phase = .ready
        default:
            break
        }
    }

    // MARK: - Scroll controls

    /// Space: start a rehearsal from ready, or pause and resume a live run.
    public mutating func togglePlayback(at now: Date) -> [Command] {
        switch phase {
        case .ready:
            return begin(.rehearsal, at: now)
        case .live:
            scroll.togglePlayback(at: now)
            return []
        default:
            return []
        }
    }

    public mutating func setSpeed(_ wordsPerMinute: Double, at now: Date) {
        scroll.setSpeed(wordsPerMinute, at: now)
    }

    public mutating func nudge(byLines lines: Double, at now: Date) {
        scroll.nudge(byLines: lines, at: now)
    }

    public mutating func jumpToPreviousParagraph(at now: Date) {
        scroll.jumpToPreviousBlock(at: now)
    }

    public mutating func jumpToNextParagraph(at now: Date) {
        scroll.jumpToNextBlock(at: now)
    }

    public mutating func rewindToStart(at now: Date) {
        scroll.seek(to: 0, at: now)
    }

    /// Takes a new layout (new text, font size, or width) without losing the place.
    public mutating func relayout(_ layout: PrompterLayout, at now: Date) {
        scroll.relayout(layout, at: now)
    }
}
