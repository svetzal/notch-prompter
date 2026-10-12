import Foundation
import Testing
@testable import NotchPrompterKit

private let start = Date(timeIntervalSinceReferenceDate: 5_000)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

/// Four one-second lines at 60 wpm, with a three-second countdown.
private func makeSession(countdown: TimeInterval = 3) -> TakeSession {
    TakeSession(layout: layout([.speech("a b"), .speech("c d")], width: 10), wordsPerMinute: 60, countdown: countdown)
}

@Suite("Take session")
struct TakeSessionTests {

    @Test("starts hidden; showing the prompter makes it ready")
    func show() {
        var session = makeSession()
        #expect(!session.isPrompterVisible)
        #expect(session.showPrompter() == [.showPrompter])
        #expect(session.phase == .ready)
        #expect(session.showPrompter() == [])
    }

    @Test("a recorded take counts down, then starts scrolling and recording together")
    func recordedTake() {
        var session = makeSession()
        let commands = session.begin(.recording, at: at(0))
        #expect(commands == [.showPrompter, .scheduleCountdownEnd(at(3))])
        #expect(session.countdownRemaining(at: at(0.2)) == 3)
        #expect(session.countdownRemaining(at: at(2.9)) == 1)
        #expect(session.position(at: at(2)) == 0)

        #expect(session.countdownDidEnd(scheduledFor: at(3), at: at(3)) == [.startRecording])
        #expect(session.phase == .live(.recording, startedAt: at(3)))
        #expect(session.isRecording)
        #expect(session.position(at: at(4.5)) == 1.5)
        #expect(session.elapsed(at: at(4.5)) == 1.5)
    }

    @Test("stopping a recorded take stops recording and waits for the file")
    func stopRecordedTake() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.recording, at: at(0))
        #expect(session.stop(at: at(2)) == [.stopRecording])
        #expect(session.phase == .finishing)
        #expect(session.isRecording)
        #expect(session.stop(at: at(2.5)) == [])

        session.recordingDidEnd(at: at(3))
        #expect(session.phase == .ready)
        #expect(session.position(at: at(10)) == 2)
    }

    @Test("with no countdown, a take goes live at once")
    func noCountdown() {
        var session = makeSession(countdown: 0)
        #expect(session.begin(.recording, at: at(0)) == [.showPrompter, .startRecording])
        #expect(session.phase == .live(.recording, startedAt: at(0)))
    }

    @Test("space in ready starts a rehearsal, which never records")
    func rehearsal() {
        var session = makeSession()
        _ = session.showPrompter()
        #expect(session.togglePlayback(at: at(0)) == [.scheduleCountdownEnd(at(3))])
        #expect(session.countdownDidEnd(scheduledFor: at(3), at: at(3)) == [])
        #expect(session.phase == .live(.rehearsal, startedAt: at(3)))
        #expect(!session.isRecording)
    }

    @Test("space during a live run pauses and resumes the scroll only")
    func pauseDuringTake() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.recording, at: at(0))
        #expect(session.togglePlayback(at: at(1)) == [])
        #expect(session.position(at: at(5)) == 1)
        #expect(session.phase == .live(.recording, startedAt: at(0)))
        _ = session.togglePlayback(at: at(5))
        #expect(session.position(at: at(6)) == 2)
    }

    @Test("stopping during the countdown cancels it, and the stale timer does nothing")
    func cancelCountdown() {
        var session = makeSession()
        _ = session.begin(.recording, at: at(0))
        #expect(session.stop(at: at(1)) == [])
        #expect(session.phase == .ready)
        #expect(session.countdownDidEnd(scheduledFor: at(3), at: at(3)) == [])

        _ = session.begin(.recording, at: at(2))
        #expect(session.countdownDidEnd(scheduledFor: at(3), at: at(3)) == [])
        #expect(session.countdownDidEnd(scheduledFor: at(5), at: at(5)) == [.startRecording])
    }

    @Test("escape steps back: live rehearsal to ready, ready to hidden")
    func escapeSteps() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.rehearsal, at: at(0))
        #expect(session.stop(at: at(1)) == [])
        #expect(session.phase == .ready)
        #expect(session.stop(at: at(1)) == [.hidePrompter])
        #expect(session.phase == .hidden)
        #expect(session.stop(at: at(1)) == [])
    }

    @Test("a take cannot start while another is running")
    func noOverlap() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.rehearsal, at: at(0))
        #expect(!session.canBegin)
        #expect(session.begin(.recording, at: at(1)) == [])
    }

    @Test("a take that would start at the end starts from the top")
    func restartsFromTop() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.rehearsal, at: at(0))
        _ = session.stop(at: at(100))
        #expect(session.position(at: at(100)) == 4)
        _ = session.begin(.rehearsal, at: at(100))
        #expect(session.position(at: at(100)) == 0)
    }

    @Test("a take starts from wherever the reader parked it")
    func startsFromParkedPosition() {
        var session = makeSession(countdown: 0)
        _ = session.showPrompter()
        session.jumpToNextParagraph(at: at(0))
        _ = session.begin(.recording, at: at(0))
        #expect(session.position(at: at(0.5)) == 2.5)
    }

    @Test("a recording that ends on its own returns to ready")
    func unexpectedEnd() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.recording, at: at(0))
        session.recordingDidEnd(at: at(1))
        #expect(session.phase == .ready)
        #expect(!session.isRecording)
    }

    @Test("rewind, nudge, and speed act on the scroll")
    func scrollControls() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.rehearsal, at: at(0))
        session.setSpeed(120, at: at(1))
        #expect(session.position(at: at(1.5)) == 2)
        session.nudge(byLines: -1, at: at(1.5))
        #expect(session.position(at: at(1.5)) == 1)
        session.rewindToStart(at: at(1.5))
        #expect(session.position(at: at(1.5)) == 0)
    }
}

@Suite("Take status")
struct TakeStatusTests {

    @Test("hidden and ready both read as ready, and a take can start")
    func ready() {
        var session = makeSession()
        #expect(session.status(at: at(0)) == .ready)
        #expect(!session.isRunning)
        _ = session.showPrompter()
        #expect(session.status(at: at(0)) == .ready)
        #expect(!session.isRunning)
    }

    @Test("the countdown shows whole seconds left and which kind of run follows")
    func countdown() {
        var session = makeSession()
        _ = session.begin(.recording, at: at(0))
        #expect(session.status(at: at(0.5)) == .countingDown(.recording, remaining: 3))
        #expect(session.status(at: at(2.5)) == .countingDown(.recording, remaining: 1))
        #expect(session.isRunning)
    }

    @Test("a rehearsal says whether its scroll is paused")
    func rehearsing() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.rehearsal, at: at(0))
        #expect(session.status(at: at(1)) == .rehearsing(isPaused: false))
        _ = session.togglePlayback(at: at(1))
        #expect(session.status(at: at(2)) == .rehearsing(isPaused: true))
        #expect(session.isRunning)
    }

    @Test("a recording shows its elapsed time, then saving while the file closes")
    func recording() {
        var session = makeSession(countdown: 0)
        _ = session.begin(.recording, at: at(0))
        #expect(session.status(at: at(65)) == .recording(elapsed: 65))
        _ = session.stop(at: at(70))
        #expect(session.status(at: at(71)) == .saving)
        #expect(session.isRunning)
        session.recordingDidEnd(at: at(72))
        #expect(session.status(at: at(72)) == .ready)
        #expect(!session.isRunning)
    }
}

@Suite("Prompter keys")
struct PrompterKeyCommandTests {

    @Test("maps plain keys", arguments: [
        (" ", PrompterKeyCommand.togglePlayback), ("\u{1B}", .stop), ("=", .faster), ("+", .faster),
        ("-", .slower), ("\u{F700}", .nudgeBack), ("\u{F701}", .nudgeForward),
        ("\u{F702}", .previousParagraph), ("\u{F703}", .nextParagraph), ("\u{F729}", .rewindToStart)
    ])
    func plainKeys(characters: String, command: PrompterKeyCommand) {
        #expect(PrompterKeyCommand(characters: characters, modifiers: []) == command)
    }

    @Test("shift does not change the meaning")
    func shift() {
        #expect(PrompterKeyCommand(characters: "+", modifiers: .shift) == .faster)
    }

    @Test("command keys change text size and rewind")
    func commandKeys() {
        #expect(PrompterKeyCommand(characters: "=", modifiers: .command) == .largerText)
        #expect(PrompterKeyCommand(characters: "-", modifiers: .command) == .smallerText)
        #expect(PrompterKeyCommand(characters: "\u{F700}", modifiers: .command) == .rewindToStart)
    }

    @Test("leaves other keys and combinations alone")
    func ignores() {
        #expect(PrompterKeyCommand(characters: "a", modifiers: []) == nil)
        #expect(PrompterKeyCommand(characters: " ", modifiers: .command) == nil)
        #expect(PrompterKeyCommand(characters: " ", modifiers: .option) == nil)
        #expect(PrompterKeyCommand(characters: "ab", modifiers: []) == nil)
    }

    @Test("every command has a label and a summary")
    func labels() {
        for command in PrompterKeyCommand.allCases {
            #expect(!command.keyLabel.isEmpty)
            #expect(!command.summary.isEmpty)
        }
    }
}

@Suite("Take in progress")
struct TakeInProgressTests {

    @Test("a recorded take holds its settings from the countdown until the file closes; a rehearsal does not")
    func takeInProgress() {
        var session = makeSession()
        #expect(!session.isTakeInProgress)
        _ = session.begin(.rehearsal, at: at(0))
        #expect(!session.isTakeInProgress)
        _ = session.stop(at: at(1))

        _ = session.begin(.recording, at: at(2))
        #expect(session.isTakeInProgress)
        _ = session.countdownDidEnd(scheduledFor: at(5), at: at(5))
        #expect(session.isTakeInProgress)
        _ = session.stop(at: at(6))
        #expect(session.isTakeInProgress)
        session.recordingDidEnd(at: at(7))
        #expect(!session.isTakeInProgress)
    }
}
