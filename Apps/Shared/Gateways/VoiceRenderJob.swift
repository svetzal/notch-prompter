import AVFoundation
import NotchPrompterKit

/// One clean-up's engine, reader, and writer.
///
/// Once ``run()`` starts, every member is used only on `queue`: the writer's
/// readiness callbacks, the offline render, and the engine's input block all
/// run there. That confinement is what makes `@unchecked Sendable` honest.
final class VoiceRenderJob: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.mojility.notch-prompter.voice-clean-up")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let audioInput: AVAssetWriterInput
    private let videoPairs: [(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)]
    private let engine: VoiceChainEngine
    private let feed: PCMFeed
    private let compensation: LatencyCompensation
    private let rendered: AVAudioPCMBuffer
    private let kept: AVAudioPCMBuffer
    /// The source movie's duration. The new movie ends exactly there.
    private let duration: CMTime

    private var renderedFrames = 0
    private var outputFrames = 0
    private var openInputs: Int
    private var continuation: CheckedContinuation<VoiceProcessingReport, Error>?

    init(
        asset: AVAsset,
        duration: CMTime,
        metadata: [AVMetadataItem],
        audioTrack: AVAssetTrack,
        videoTracks: [PassthroughTrack],
        destination: URL,
        format: AVAudioFormat,
        chain: [(component: AudioUnitComponent, unit: AVAudioUnit)]
    ) throws {
        self.duration = duration
        guard let rendered = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: VoiceProcessor.framesPerRender),
              let kept = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: VoiceProcessor.framesPerRender) else {
            throw VoiceProcessorError.renderFailed("no memory for the audio buffers")
        }
        self.rendered = rendered
        self.kept = kept
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VoiceProcessorError.cannotRead(error.localizedDescription)
        }
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        } catch {
            throw VoiceProcessorError.cannotWrite(error.localizedDescription)
        }
        writer.metadata = metadata
        // The source's time scale, so the movie can end exactly where the source ends.
        if duration.timescale > 0 {
            writer.movieTimeScale = duration.timescale
        }
        videoPairs = videoTracks.map(Self.passthrough)
        for (output, input) in videoPairs {
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw VoiceProcessorError.cannotWrite("the video cannot be copied")
            }
            reader.add(output)
            writer.add(input)
        }
        let audioOutput = Self.decodedAudio(of: audioTrack, as: format)
        audioInput = Self.encodedAudio(as: format)
        guard reader.canAdd(audioOutput), writer.canAdd(audioInput) else {
            throw VoiceProcessorError.cannotWrite("the audio cannot be re-encoded")
        }
        reader.add(audioOutput)
        writer.add(audioInput)
        openInputs = videoPairs.count + 1

        feed = try PCMFeed(output: audioOutput, reader: reader, format: format)
        engine = try VoiceChainEngine(chain: chain, format: format, feed: feed)
        compensation = LatencyCompensation(latencies: engine.latencies, sampleRate: format.sampleRate)
    }

    /// Copies a video track's samples as they are, with its transform, time scale, and metadata.
    private static func passthrough(_ video: PassthroughTrack) -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        let output = AVAssetReaderTrackOutput(track: video.track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: video.formatHint)
        input.transform = video.transform
        input.mediaTimeScale = video.timeScale
        input.metadata = video.metadata
        input.expectsMediaDataInRealTime = false
        return (output, input)
    }

    /// Decodes the take's audio to non-interleaved floating point in `format`.
    private static func decodedAudio(of track: AVAssetTrack, as format: AVAudioFormat) -> AVAssetReaderTrackOutput {
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false
        return output
    }

    /// Encodes the processed audio to AAC at the format's rate and channel count.
    private static func encodedAudio(as format: AVAudioFormat) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: VoiceProcessor.bitRatePerChannel * Int(format.channelCount)
        ])
        input.expectsMediaDataInRealTime = false
        return input
    }

    // MARK: - Running

    func run() async throws -> VoiceProcessingReport {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.start()
            }
        }
    }

    private func start() {
        guard reader.startReading() else {
            return fail(VoiceProcessorError.cannotRead(reader.error?.localizedDescription ?? "unknown error"))
        }
        guard writer.startWriting() else {
            return fail(VoiceProcessorError.cannotWrite(writer.error?.localizedDescription ?? "unknown error"))
        }
        writer.startSession(atSourceTime: .zero)
        for index in videoPairs.indices {
            videoPairs[index].input.requestMediaDataWhenReady(on: queue) { [self] in
                copyVideo(index)
            }
        }
        audioInput.requestMediaDataWhenReady(on: queue) { [self] in
            renderAudio()
        }
    }

    private func copyVideo(_ index: Int) {
        let (output, input) = videoPairs[index]
        while continuation != nil, input.isReadyForMoreMediaData {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    return fail(VoiceProcessorError.cannotRead(reader.error?.localizedDescription ?? "unknown error"))
                }
                input.markAsFinished()
                return inputDidFinish()
            }
            guard input.append(sample) else {
                return fail(VoiceProcessorError.cannotWrite(writer.error?.localizedDescription ?? "the video was refused"))
            }
        }
    }

    private func renderAudio() {
        while continuation != nil, audioInput.isReadyForMoreMediaData {
            if let inputFrames = feed.inputFrames,
               renderedFrames >= compensation.framesToRender(inputFrames: inputFrames) {
                audioInput.markAsFinished()
                return inputDidFinish()
            }
            do {
                try renderChunk()
            } catch {
                return fail(error)
            }
        }
    }

    /// Renders one chunk and appends the part of it that belongs to the output.
    private func renderChunk() throws {
        let didRender = try engine.render(into: rendered)
        if let failure = feed.failure {
            throw failure as? VoiceProcessorError ?? VoiceProcessorError.cannotRead(failure.localizedDescription)
        }
        guard didRender else { return }
        let start = renderedFrames
        renderedFrames += Int(rendered.frameLength)
        let keep = compensation.keptFrames(ofRendered: start..<renderedFrames, inputFrames: feed.inputFrames)
        guard !keep.isEmpty, let firstTime = feed.firstTime else { return }
        let sample = try sampleBuffer(
            frames: (keep.lowerBound - start)..<(keep.upperBound - start),
            at: CMTimeAdd(firstTime, CMTime(
                value: CMTimeValue(compensation.outputFrame(forRendered: keep.lowerBound)),
                timescale: CMTimeScale(VoiceProcessor.sampleRate)
            ))
        )
        guard audioInput.append(sample) else {
            throw VoiceProcessorError.cannotWrite(writer.error?.localizedDescription ?? "the audio was refused")
        }
        outputFrames += keep.count
    }

    /// The rendered frames in `frames`, as a sample buffer that starts at `time`.
    private func sampleBuffer(frames: Range<Int>, at time: CMTime) throws -> CMSampleBuffer {
        guard let source = rendered.floatChannelData, let destination = kept.floatChannelData else {
            throw VoiceProcessorError.renderFailed("the rendered audio is not floating point")
        }
        for channel in 0..<Int(rendered.format.channelCount) {
            (destination[channel]).update(from: source[channel] + frames.lowerBound, count: frames.count)
        }
        kept.frameLength = AVAudioFrameCount(frames.count)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(VoiceProcessor.sampleRate)),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        var status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: kept.format.formatDescription,
            sampleCount: frames.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else {
            throw VoiceProcessorError.renderFailed("could not wrap the audio (\(status))")
        }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sample,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: kept.audioBufferList
        )
        guard status == noErr else {
            throw VoiceProcessorError.renderFailed("could not copy the audio (\(status))")
        }
        return sample
    }

    // MARK: - Ending

    private func inputDidFinish() {
        openInputs -= 1
        guard openInputs == 0 else { return }
        engine.stop()
        // The reader pads the audio to the movie's end in whole frames; the
        // session end trims that rounding, so the duration does not change.
        writer.endSession(atSourceTime: duration)
        writer.finishWriting { [self] in
            queue.async { [self] in
                guard writer.status == .completed else {
                    return fail(VoiceProcessorError.cannotWrite(writer.error?.localizedDescription ?? "unknown error"))
                }
                finish(.success(VoiceProcessingReport(
                    plugins: zip(engine.chain, engine.latencies).map {
                        .init(name: $0.component.name, codes: $0.component.codes, latency: $1)
                    },
                    latencyFrames: compensation.latencyFrames,
                    sampleRate: VoiceProcessor.sampleRate,
                    channelCount: Int(rendered.format.channelCount),
                    inputFrames: feed.inputFrames ?? 0,
                    outputFrames: outputFrames
                )))
            }
        }
    }

    private func fail(_ error: Error) {
        guard continuation != nil else { return }
        reader.cancelReading()
        if writer.status == .writing {
            writer.cancelWriting()
        }
        engine.stop()
        finish(.failure(error))
    }

    private func finish(_ result: Result<VoiceProcessingReport, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
