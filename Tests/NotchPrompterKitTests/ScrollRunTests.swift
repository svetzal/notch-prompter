import Foundation
import Testing
@testable import NotchPrompterKit

private let start = Date(timeIntervalSinceReferenceDate: 1_000)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

@Suite("Scroll timeline")
struct ScrollTimelineTests {

    // At 60 wpm one word takes one second.
    // Lines: "one two" (2 s), pause 3 s, "three" (1 s), a note line (2 s).
    let timeline = ScrollTimeline(layout: layout([.speech("one two"), .pause(3), .speech("three"), .note("look")]))

    @Test("speech lines take their words' time, pauses their seconds")
    func durations() {
        #expect(timeline.duration(ofLine: 0, wordsPerMinute: 60) == 2)
        #expect(timeline.duration(ofLine: 1, wordsPerMinute: 60) == 3)
        #expect(timeline.duration(ofLine: 1, wordsPerMinute: 240) == 3)
        #expect(timeline.duration(ofLine: 2, wordsPerMinute: 120) == 0.5)
        #expect(timeline.duration(ofLine: 3, wordsPerMinute: 60) == ScrollTimeline.noteLineWords)
    }

    @Test("advances smoothly within a line")
    func withinLine() {
        #expect(timeline.advance(from: 0, by: 1, wordsPerMinute: 60) == 0.5)
    }

    @Test("crosses lines and holds through a pause")
    func acrossPause() {
        #expect(timeline.advance(from: 0, by: 2, wordsPerMinute: 60) == 1)
        #expect(timeline.advance(from: 0, by: 3.5, wordsPerMinute: 60) == 1.5)
        #expect(timeline.advance(from: 0, by: 5.5, wordsPerMinute: 60) == 2.5)
    }

    @Test("a pause holds for the same time at any speed")
    func pauseIgnoresSpeed() {
        // At 120 wpm, line 0 takes 1 s; the pause still takes 3 s.
        #expect(timeline.advance(from: 0, by: 4, wordsPerMinute: 120) == 2)
    }

    @Test("stops at the end")
    func stopsAtEnd() {
        #expect(timeline.advance(from: 0, by: 1_000, wordsPerMinute: 60) == 4)
    }

    @Test("does not move without time or speed")
    func noMovement() {
        #expect(timeline.advance(from: 1.5, by: 0, wordsPerMinute: 60) == 1.5)
        #expect(timeline.advance(from: 1.5, by: 10, wordsPerMinute: 0) == 1.5)
    }

    @Test("reports the time left to the end")
    func remaining() {
        #expect(timeline.remainingTime(from: 0, wordsPerMinute: 60) == 8)
        #expect(timeline.remainingTime(from: 1.5, wordsPerMinute: 60) == 4.5)
    }
}

@Suite("Scroll run")
struct ScrollRunTests {

    // Four one-second lines at 60 wpm: blocks start at 0 and 2.
    func makeRun() -> ScrollRun {
        ScrollRun(layout: layout([.speech("a b"), .speech("c d")], width: 10), wordsPerMinute: 60)
    }

    @Test("stays put until played")
    func idle() {
        let run = makeRun()
        #expect(!run.isPlaying)
        #expect(run.position(at: at(5)) == 0)
    }

    @Test("position is a function of time since play")
    func plays() {
        var run = makeRun()
        run.play(at: at(0))
        #expect(run.position(at: at(1.5)) == 1.5)
        #expect(run.isFinished(at: at(9)))
    }

    @Test("pausing freezes the position; resuming continues from it")
    func pauseResume() {
        var run = makeRun()
        run.play(at: at(0))
        run.pause(at: at(1))
        #expect(run.position(at: at(10)) == 1)
        run.togglePlayback(at: at(10))
        #expect(run.position(at: at(11.5)) == 2.5)
    }

    @Test("a speed change applies from that moment on")
    func speedChange() {
        var run = makeRun()
        run.play(at: at(0))
        run.setSpeed(120, at: at(1))
        #expect(run.wordsPerMinute == 120)
        #expect(run.position(at: at(1.5)) == 2)
    }

    @Test("nudges move by lines and keep playing")
    func nudges() {
        var run = makeRun()
        run.play(at: at(0))
        run.nudge(byLines: -1, at: at(1.5))
        #expect(run.position(at: at(1.5)) == 0.5)
        #expect(run.position(at: at(2)) == 1)
        run.nudge(byLines: -10, at: at(2))
        #expect(run.position(at: at(2)) == 0)
    }

    @Test("jumps move between paragraphs")
    func jumps() {
        var run = makeRun()
        run.seek(to: 3, at: at(0))
        run.jumpToPreviousBlock(at: at(0))
        #expect(run.position(at: at(0)) == 2)
        run.jumpToPreviousBlock(at: at(0))
        #expect(run.position(at: at(0)) == 0)
        run.jumpToNextBlock(at: at(0))
        #expect(run.position(at: at(0)) == 2)
    }

    @Test("relayout keeps the place in the paragraph")
    func relayout() {
        let blocks: [PrompterBlock] = [.speech("aaaa bbbb cccc dddd")]
        var run = ScrollRun(layout: layout(blocks, width: 40), wordsPerMinute: 60, position: 2)
        run.relayout(layout(blocks, width: 90), at: at(0))
        #expect(run.position(at: at(0)) == 1)
        #expect(run.layout.lines.count == 2)
    }
}
