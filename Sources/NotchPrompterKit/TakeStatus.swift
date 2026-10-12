import Foundation

/// What the window says about the run, at a glance.
///
/// The main window's toolbar shows this in its centre: ready, the countdown,
/// a rehearsal, the time a recording has run, the movie file closing, or
/// the take's voice clean-up.
public enum TakeStatus: Equatable, Sendable {
    /// Nothing is running; a take or a rehearsal can start.
    case ready
    /// Whole seconds before the run of this mode goes live.
    case countingDown(TakeSession.Mode, remaining: Int)
    /// The prompter is running without recording.
    case rehearsing(isPaused: Bool)
    /// The prompter and the recording are running.
    case recording(elapsed: TimeInterval)
    /// Recording has stopped and the movie file is still closing.
    case saving
    /// The saved take's audio is going through the voice clean-up chain.
    case cleaningUpVoice
}

extension TakeSession {

    /// Whether a countdown, a run, or the end of a recording is under way,
    /// so Stop takes the place of Record.
    public var isRunning: Bool {
        !canBegin
    }

    public func status(at now: Date) -> TakeStatus {
        switch phase {
        case .hidden, .ready:
            .ready
        case .countingDown(let mode, _):
            .countingDown(mode, remaining: countdownRemaining(at: now) ?? 1)
        case .live(.rehearsal, _):
            .rehearsing(isPaused: !scroll.isPlaying)
        case .live(.recording, _):
            .recording(elapsed: elapsed(at: now) ?? 0)
        case .finishing:
            .saving
        case .cleaningUpVoice:
            .cleaningUpVoice
        }
    }
}
