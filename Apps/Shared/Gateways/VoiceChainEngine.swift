import AVFoundation
import NotchPrompterKit

/// The chain's plug-ins in an `AVAudioEngine` in offline manual rendering
/// mode: input, then each plug-in in order, then output.
///
/// Used only on the render job's queue.
final class VoiceChainEngine: @unchecked Sendable {

    let chain: [(component: AudioUnitComponent, unit: AVAudioUnit)]
    /// Each plug-in's latency in seconds, read once its render resources
    /// exist at the take's sample rate. Before that a plug-in may report its
    /// latency at another rate.
    let latencies: [TimeInterval]
    private let engine: AVAudioEngine

    /// Starts the chain, fed from `feed`.
    init(chain: [(component: AudioUnitComponent, unit: AVAudioUnit)], format: AVAudioFormat, feed: PCMFeed) throws {
        let engine = AVAudioEngine()
        latencies = try Self.start(engine, chain: chain, format: format, feed: feed)
        self.engine = engine
        self.chain = chain
    }

    /// Renders the next frames into `buffer`, up to its capacity. False when
    /// the engine asks to be called again.
    func render(into buffer: AVAudioPCMBuffer) throws -> Bool {
        let status: AVAudioEngineManualRenderingStatus
        do {
            status = try engine.renderOffline(buffer.frameCapacity, to: buffer)
        } catch {
            throw VoiceProcessorError.renderFailed(error.localizedDescription)
        }
        switch status {
        case .success:
            return true
        case .cannotDoInCurrentContext:
            return false
        default:
            throw VoiceProcessorError.renderFailed("render status \(status.rawValue)")
        }
    }

    func stop() {
        engine.stop()
    }

    /// Wires input → each plug-in in order → output, and starts the engine
    /// in offline mode. Returns each plug-in's latency, read once its render
    /// resources exist at the take's sample rate.
    private static func start(
        _ engine: AVAudioEngine,
        chain: [(component: AudioUnitComponent, unit: AVAudioUnit)],
        format: AVAudioFormat,
        feed: PCMFeed
    ) throws -> [TimeInterval] {
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: VoiceProcessor.framesPerRender)
        } catch {
            throw VoiceProcessorError.renderFailed(error.localizedDescription)
        }
        // A plug-in that refuses the format would raise an exception on
        // connect, so ask each one first.
        for (component, unit) in chain {
            let audioUnit = unit.auAudioUnit
            guard audioUnit.inputBusses.count >= 1, audioUnit.outputBusses.count >= 1 else {
                throw VoiceProcessorError.unsupportedFormat(plugin: component.name, detail: "it has no audio input")
            }
            do {
                try audioUnit.inputBusses[0].setFormat(format)
                try audioUnit.outputBusses[0].setFormat(format)
            } catch {
                throw VoiceProcessorError.unsupportedFormat(
                    plugin: component.name,
                    detail: "it does not take \(format.channelCount)-channel audio at 48 kHz"
                )
            }
            engine.attach(unit)
        }
        var previous: AVAudioNode = engine.inputNode
        for (_, unit) in chain {
            engine.connect(previous, to: unit, format: format)
            previous = unit
        }
        engine.connect(previous, to: engine.outputNode, format: format)
        let accepted = engine.inputNode.setManualRenderingInputPCMFormat(format) { [feed] frameCount in
            feed.provide(frameCount)
        }
        guard accepted else {
            throw VoiceProcessorError.renderFailed("the engine does not take the take's audio format")
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceProcessorError.renderFailed(error.localizedDescription)
        }
        return chain.map(\.unit.auAudioUnit.latency)
    }
}

/// Feeds the engine's input from the take's decoded audio, on the movie's
/// timeline: a gap between decoded buffers becomes silence and an overlap
/// is dropped (see ``SampleContinuity``), and after the last frame the feed
/// gives silence, which the chain needs to play out its latency.
///
/// Used only from the render, on the job's queue.
final class PCMFeed: @unchecked Sendable {

    private let output: AVAssetReaderTrackOutput
    private let reader: AVAssetReader
    private let format: AVAudioFormat
    /// The buffer handed to the engine on each pull.
    private let buffer: AVAudioPCMBuffer
    private var pending: AVAudioPCMBuffer?
    private var pendingOffset = 0
    private var silenceDue = 0
    /// Frames fed from the take's timeline so far, decoded audio and gap silence together.
    private var timelineFrames = 0

    /// How many frames the take's audio has, once the last one has been read.
    private(set) var inputFrames: Int?
    /// The presentation time of the take's first audio frame.
    private(set) var firstTime: CMTime?
    private(set) var failure: Error?

    init(output: AVAssetReaderTrackOutput, reader: AVAssetReader, format: AVAudioFormat) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: VoiceProcessor.framesPerRender) else {
            throw VoiceProcessorError.renderFailed("no memory for the audio buffers")
        }
        self.output = output
        self.reader = reader
        self.format = format
        self.buffer = buffer
    }

    /// The engine's input block: the next `frameCount` frames.
    func provide(_ frameCount: AVAudioFrameCount) -> UnsafePointer<AudioBufferList>? {
        let wanted = min(Int(frameCount), Int(buffer.frameCapacity))
        var filled = 0
        while filled < wanted {
            if silenceDue > 0 {
                let count = min(silenceDue, wanted - filled)
                fillSilence(at: filled, count: count)
                silenceDue -= count
                timelineFrames += count
                filled += count
            } else if let pending, pendingOffset < Int(pending.frameLength) {
                let count = min(Int(pending.frameLength) - pendingOffset, wanted - filled)
                copy(from: pending, offset: pendingOffset, to: filled, count: count)
                pendingOffset += count
                timelineFrames += count
                filled += count
            } else if inputFrames == nil, readNext() {
                continue
            } else {
                if inputFrames == nil {
                    inputFrames = timelineFrames
                }
                fillSilence(at: filled, count: wanted - filled)
                filled = wanted
            }
        }
        buffer.frameLength = AVAudioFrameCount(wanted)
        return buffer.audioBufferList
    }

    /// Reads the next decoded buffer into `pending`. False at the end of the audio.
    private func readNext() -> Bool {
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                failure = reader.error ?? VoiceProcessorError.cannotRead("the reader stopped")
            }
            return false
        }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return true }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        let first = firstTime ?? time
        firstTime = first
        let start = SampleContinuity.frame(
            atSeconds: time.seconds, firstSampleSeconds: first.seconds, sampleRate: format.sampleRate
        )
        var skip = 0
        switch SampleContinuity.adjustment(expectedFrame: timelineFrames, bufferStartFrame: start) {
        case .none: break
        case .insertSilence(let count): silenceDue = count
        case .dropFrames(let count): skip = count
        }
        guard let decoded = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            failure = VoiceProcessorError.renderFailed("no memory for the decoded audio")
            return false
        }
        // The buffer list's byte sizes follow the frame length, and the copy checks them.
        decoded.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(frames), into: decoded.mutableAudioBufferList
        )
        guard status == noErr else {
            failure = VoiceProcessorError.cannotRead("decoded audio could not be copied (\(status))")
            return false
        }
        pending = decoded
        pendingOffset = min(skip, frames)
        return true
    }

    private func fillSilence(at offset: Int, count: Int) {
        guard count > 0, let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(format.channelCount) {
            (channels[channel] + offset).update(repeating: 0, count: count)
        }
    }

    private func copy(from source: AVAudioPCMBuffer, offset: Int, to destinationOffset: Int, count: Int) {
        guard let from = source.floatChannelData, let into = buffer.floatChannelData else { return }
        for channel in 0..<Int(format.channelCount) {
            (into[channel] + destinationOffset).update(from: from[channel] + offset, count: count)
        }
    }
}
