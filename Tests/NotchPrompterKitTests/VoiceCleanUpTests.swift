import Foundation
import Testing
@testable import NotchPrompterKit

@Suite("Voice clean-up files")
struct VoiceCleanUpFilesTests {

    @Test("the unprocessed take sits beside the take, ending in -original")
    func originalName() {
        #expect(VoiceCleanUpFiles.originalName(for: "2026-10-12-143205-launch.mov") == "2026-10-12-143205-launch-original.mov")
        #expect(VoiceCleanUpFiles.originalName(for: "take-vertical.mov") == "take-vertical-original.mov")
    }

    @Test("the first clean-up keeps the recorded take as the original, then writes the take")
    func firstCleanUp() {
        let files = VoiceCleanUpFiles(takeName: "a.mov", existing: ["a.mov", "b.mov"])
        #expect(files.original == "a-original.mov")
        #expect(files.keepsTakeAsOriginal)
        #expect(files.working == ".a-cleaning.mov")
    }

    @Test("cleaning up again reads the existing original and replaces the take, never stacking")
    func again() {
        let files = VoiceCleanUpFiles(takeName: "a.mov", existing: ["a.mov", "A-Original.MOV"])
        #expect(files.original == "a-original.mov")
        #expect(!files.keepsTakeAsOriginal)
    }

    @Test("after a failure, a take that is gone gets its original back; otherwise both stay")
    func recovery() {
        let first = VoiceCleanUpFiles(takeName: "a.mov", existing: ["a.mov"])
        #expect(first.recovery(takeExists: false) == .restoreOriginal)
        #expect(first.recovery(takeExists: true) == .keepBoth)
    }
}

@Suite("Latency compensation")
struct LatencyCompensationTests {

    @Test("latencies add up and round to whole frames")
    func latencyFrames() {
        #expect(LatencyCompensation(latencies: [0.002, 0.015011], sampleRate: 48_000).latencyFrames == 817)
        #expect(LatencyCompensation(latencies: [], sampleRate: 48_000).latencyFrames == 0)
        #expect(LatencyCompensation(latencies: [-1], sampleRate: 48_000).latencyFrames == 0)
    }

    @Test("the chain renders the latency past the input's end, so nothing is lost")
    func framesToRender() {
        let compensation = LatencyCompensation(latencyFrames: 96)
        #expect(compensation.framesToRender(inputFrames: 48_000) == 48_096)
    }

    @Test("the leading latency is trimmed and the output is exactly as long as the input")
    func keptFrames() {
        let compensation = LatencyCompensation(latencyFrames: 96)
        // Input length still unknown: keep everything after the latency.
        #expect(compensation.keptFrames(ofRendered: 0..<64, inputFrames: nil) == 64..<64)
        #expect(compensation.keptFrames(ofRendered: 64..<128, inputFrames: nil) == 96..<128)
        #expect(compensation.keptFrames(ofRendered: 128..<192, inputFrames: nil) == 128..<192)
        // Input known: stop at input length plus latency.
        #expect(compensation.keptFrames(ofRendered: 1_000..<1_200, inputFrames: 1_050) == 1_000..<1_146)
        #expect(compensation.keptFrames(ofRendered: 1_146..<1_200, inputFrames: 1_050) == 1_146..<1_146)
    }

    @Test("over a whole render, kept frames add up to the input length", arguments: [0, 1, 96, 4_096, 30_000])
    func totalKept(latency: Int) {
        let compensation = LatencyCompensation(latencyFrames: latency)
        let input = 100_003
        let total = compensation.framesToRender(inputFrames: input)
        var kept = 0
        var rendered = 0
        while rendered < total {
            let chunk = min(4_096, total - rendered)
            kept += compensation.keptFrames(ofRendered: rendered..<(rendered + chunk), inputFrames: input).count
            rendered += chunk
        }
        #expect(kept == input)
    }

    @Test("a rendered frame maps back to the input frame it came from")
    func outputFrame() {
        let compensation = LatencyCompensation(latencyFrames: 96)
        #expect(compensation.outputFrame(forRendered: 96) == 0)
        #expect(compensation.outputFrame(forRendered: 1_096) == 1_000)
    }
}

@Suite("Sample continuity")
struct SampleContinuityTests {

    @Test("a buffer that starts where the last one ended needs nothing")
    func contiguous() {
        #expect(SampleContinuity.adjustment(expectedFrame: 1_024, bufferStartFrame: 1_024) == .none)
        #expect(SampleContinuity.adjustment(expectedFrame: 1_024, bufferStartFrame: 1_025) == .none)
        #expect(SampleContinuity.adjustment(expectedFrame: 1_024, bufferStartFrame: 1_023) == .none)
    }

    @Test("a gap is filled with silence, so later audio keeps its time")
    func gap() {
        #expect(SampleContinuity.adjustment(expectedFrame: 1_024, bufferStartFrame: 2_048) == .insertSilence(1_024))
    }

    @Test("an overlap drops the frames already fed")
    func overlap() {
        #expect(SampleContinuity.adjustment(expectedFrame: 2_048, bufferStartFrame: 2_000) == .dropFrames(48))
    }

    @Test("presentation times convert to frames from the first sample")
    func frameOffset() {
        #expect(SampleContinuity.frame(atSeconds: 1.5, firstSampleSeconds: 0.5, sampleRate: 48_000) == 48_000)
        #expect(SampleContinuity.frame(atSeconds: 0.5, firstSampleSeconds: 0.5, sampleRate: 48_000) == 0)
    }
}

@Suite("Interrupted clean-ups")
struct InterruptedCleanUpTests {

    @Test("an -original without its take was cut off mid clean-up, so it goes back under the take's name")
    func restore() {
        let steps = VoiceCleanUpFiles.interruptedCleanUps(in: ["a-original.mov", "b.mov", "b-original.mov"])
        #expect(steps == [.restoreOriginal(original: "a-original.mov", take: "a.mov")])
    }

    @Test("a working file left behind is removed")
    func working() {
        let steps = VoiceCleanUpFiles.interruptedCleanUps(in: [".a-cleaning.mov", "a.mov", "a-original.mov", ".DS_Store"])
        #expect(steps == [.removeWorkingFile(".a-cleaning.mov")])
    }

    @Test("both at once, in a stable order")
    func both() {
        let steps = VoiceCleanUpFiles.interruptedCleanUps(in: ["b-original.mov", ".b-cleaning.mov", "a-original.mov"])
        #expect(steps == [
            .removeWorkingFile(".b-cleaning.mov"),
            .restoreOriginal(original: "a-original.mov", take: "a.mov"),
            .restoreOriginal(original: "b-original.mov", take: "b.mov")
        ])
    }

    @Test("a take name present in other case counts as present")
    func caseInsensitive() {
        #expect(VoiceCleanUpFiles.interruptedCleanUps(in: ["A.MOV", "a-original.mov"]).isEmpty)
    }

    @Test("a folder of plain takes needs nothing")
    func clean() {
        #expect(VoiceCleanUpFiles.interruptedCleanUps(in: ["a.mov", "b-vertical.mov", ".DS_Store"]).isEmpty)
    }

    @Test("original and working names map back to the take's name")
    func names() {
        #expect(VoiceCleanUpFiles.takeName(forOriginal: "a-vertical-original.mov") == "a-vertical.mov")
        #expect(VoiceCleanUpFiles.takeName(forOriginal: "a.mov") == nil)
        #expect(VoiceCleanUpFiles.workingName(for: "a.mov") == ".a-cleaning.mov")
        #expect(VoiceCleanUpFiles.isWorkingFile(".a-cleaning.mov"))
        #expect(!VoiceCleanUpFiles.isWorkingFile("a-cleaning.mov"))
        #expect(!VoiceCleanUpFiles.isWorkingFile(".a-cropping.mov"))
    }
}
