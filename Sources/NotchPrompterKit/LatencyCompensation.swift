import Foundation

/// Keeps a processed take's audio in sync with its video.
///
/// Plug-ins with look-ahead delay their output: a sound that enters at frame
/// `n` comes out at frame `n + latency`. The chain's latency is the sum of
/// its plug-ins' latencies. To keep sync, the clean-up drops that many frames
/// from the start of the rendered audio, and renders that many frames past
/// the input's end (fed with silence) so the output is exactly as long as the
/// input. Whatever a plug-in's tail rings on past that point is not kept,
/// because the take keeps its length.
public struct LatencyCompensation: Equatable, Sendable {

    /// The chain's delay, in frames.
    public let latencyFrames: Int

    public init(latencyFrames: Int) {
        self.latencyFrames = max(0, latencyFrames)
    }

    /// The chain's delay from each plug-in's latency in seconds, rounded to whole frames.
    public init(latencies: [TimeInterval], sampleRate: Double) {
        let seconds = latencies.reduce(0) { $0 + max(0, $1) }
        self.init(latencyFrames: Int((seconds * sampleRate).rounded()))
    }

    /// How many frames to render for `inputFrames` of input.
    public func framesToRender(inputFrames: Int) -> Int {
        inputFrames + latencyFrames
    }

    /// The part of a rendered stretch that goes into the output, in rendered
    /// frame numbers (counted from the first frame rendered).
    ///
    /// `inputFrames` is `nil` while the input's length is not yet known; the
    /// output then runs on to the end of the stretch.
    public func keptFrames(ofRendered rendered: Range<Int>, inputFrames: Int?) -> Range<Int> {
        let end = inputFrames.map { min(rendered.upperBound, framesToRender(inputFrames: $0)) } ?? rendered.upperBound
        let upper = max(rendered.lowerBound, end)
        let lower = min(max(rendered.lowerBound, latencyFrames), upper)
        return lower..<upper
    }

    /// The output frame (and the input frame it came from) for a rendered frame.
    public func outputFrame(forRendered frame: Int) -> Int {
        frame - latencyFrames
    }
}

/// Keeps decoded audio on the movie's timeline when it has gaps or overlaps.
///
/// Decoded buffers carry presentation times. The chain is fed a gapless
/// stream, so a gap between buffers becomes silence and an overlap is
/// dropped. Otherwise everything after the gap would play early.
public enum SampleContinuity {

    public enum Adjustment: Equatable, Sendable {
        case none
        case insertSilence(Int)
        case dropFrames(Int)
    }

    /// Frames of difference that come from rounding times to frames, not from a real gap.
    public static let tolerance = 1

    /// What to do before feeding a buffer that starts at `bufferStartFrame`
    /// when the stream has fed frames up to `expectedFrame`.
    public static func adjustment(expectedFrame: Int, bufferStartFrame: Int) -> Adjustment {
        let difference = bufferStartFrame - expectedFrame
        if abs(difference) <= tolerance {
            return .none
        }
        return difference > 0 ? .insertSilence(difference) : .dropFrames(-difference)
    }

    /// The frame number, counted from the first sample, of a time in seconds.
    public static func frame(atSeconds seconds: Double, firstSampleSeconds: Double, sampleRate: Double) -> Int {
        Int(((seconds - firstSampleSeconds) * sampleRate).rounded())
    }
}
