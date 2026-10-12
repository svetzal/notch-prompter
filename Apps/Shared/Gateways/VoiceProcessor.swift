import AVFoundation
import NotchPrompterKit

enum VoiceProcessorError: LocalizedError {
    case noAudio
    case unsupportedFormat(plugin: String, detail: String)
    case cannotRead(String)
    case cannotWrite(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudio:
            "The take has no audio."
        case .unsupportedFormat(let plugin, let detail):
            "\(plugin) cannot process this take's audio: \(detail)"
        case .cannotRead(let detail):
            "The take's audio cannot be read: \(detail)"
        case .cannotWrite(let detail):
            "The cleaned-up take cannot be written: \(detail)"
        case .renderFailed(let detail):
            "The voice clean-up chain stopped: \(detail)"
        }
    }
}

/// What a voice clean-up did, for the log.
struct VoiceProcessingReport: Sendable {
    struct Plugin: Sendable {
        let name: String
        let codes: String
        /// The plug-in's reported latency at the take's sample rate, in seconds.
        let latency: TimeInterval
    }

    let plugins: [Plugin]
    /// Frames trimmed from the start of the rendered audio, the chain's total latency.
    let latencyFrames: Int
    let sampleRate: Double
    let channelCount: Int
    let inputFrames: Int
    let outputFrames: Int
}

/// Runs a movie's audio through a chain of Audio Units, faster than real
/// time, and writes a new movie with the processed audio.
///
/// The audio is decoded to 48 kHz floating point, rendered through the
/// plug-ins by an `AVAudioEngine` in offline manual rendering mode, and
/// encoded to AAC at 48 kHz. The video is copied sample for sample, never
/// re-encoded, and the movie's metadata is kept.
///
/// Sync is the point that matters most. ``LatencyCompensation`` trims the
/// chain's latency from the start of the rendered audio and renders that
/// many frames past the end, and the processed audio starts at the same
/// presentation time as the original, so every sound stays where it was
/// against the picture.
enum VoiceProcessor {

    static let sampleRate = 48_000.0
    static let framesPerRender: AVAudioFrameCount = 4_096
    /// Bits per second of AAC, per channel.
    static let bitRatePerChannel = 128_000

    /// Writes `source`, with its audio run through `entries` in order, to
    /// `destination`, which must not exist yet.
    static func process(
        _ source: URL,
        into destination: URL,
        through entries: [VoiceChain.Entry]
    ) async throws -> VoiceProcessingReport {
        let asset = AVURLAsset(url: source)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VoiceProcessorError.noAudio
        }
        let channels = try await channelCount(of: audioTrack)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw VoiceProcessorError.cannotRead("no format for \(channels) channels at 48 kHz")
        }
        var videoTracks: [PassthroughTrack] = []
        for track in try await asset.loadTracks(withMediaType: .video) {
            let (descriptions, transform, timeScale, metadata) = try await track.load(
                .formatDescriptions, .preferredTransform, .naturalTimeScale, .metadata
            )
            videoTracks.append(PassthroughTrack(
                track: track, formatHint: descriptions.first, transform: transform, timeScale: timeScale, metadata: metadata
            ))
        }
        var units: [AVAudioUnit] = []
        for entry in entries {
            units.append(try await AudioUnits.load(entry.component, state: entry.state))
        }
        let (duration, metadata) = try await asset.load(.duration, .metadata)
        let job = try VoiceRenderJob(
            asset: asset,
            duration: duration,
            metadata: metadata,
            audioTrack: audioTrack,
            videoTracks: videoTracks,
            destination: destination,
            format: format,
            chain: zip(entries, units).map { ($0.component, $1) }
        )
        return try await job.run()
    }

    /// The take's channel count, kept as mono or stereo.
    private static func channelCount(of track: AVAssetTrack) async throws -> AVAudioChannelCount {
        let descriptions = try await track.load(.formatDescriptions)
        let channels = descriptions.first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 1
        return min(max(1, channels), 2)
    }
}

/// A video track to copy without re-encoding.
struct PassthroughTrack {
    let track: AVAssetTrack
    let formatHint: CMFormatDescription?
    let transform: CGAffineTransform
    let timeScale: CMTimeScale
    let metadata: [AVMetadataItem]
}
