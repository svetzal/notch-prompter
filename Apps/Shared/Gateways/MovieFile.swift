import AVFoundation
import NotchPrompterKit
import os

extension Logger {
    /// Recording events, including which path gave a take its shape.
    /// Read with `log show --predicate 'subsystem == "com.mojility.notch-prompter"'`.
    static let recording = Logger(subsystem: "com.mojility.notch-prompter", category: "recording")
}

enum MovieFileError: LocalizedError {
    case noVideoTrack
    case cannotExport

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The movie has no video."
        case .cannotExport: "The movie cannot be exported."
        }
    }
}

/// Reads a finished movie's video shape, and cuts a movie down to a crop.
///
/// Thin adapters over `AVURLAsset` and `AVAssetExportSession`. The crop
/// geometry comes from the Kit's ``VideoCrop``.
enum MovieFile {

    /// What a movie's video track stores, and how it is shown.
    struct VideoTrack: Sendable {
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let nominalFrameRate: Float

        /// The size the movie plays at.
        var displayedSize: PixelSize {
            PixelSize(displaying: naturalSize, transform: preferredTransform)
        }
    }

    static func videoTrack(of url: URL) async throws -> VideoTrack {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MovieFileError.noVideoTrack
        }
        let (naturalSize, preferredTransform, frameRate) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate
        )
        return VideoTrack(naturalSize: naturalSize, preferredTransform: preferredTransform, nominalFrameRate: frameRate)
    }

    /// Re-encodes the movie at `url` to `crop`, keeping its audio, and puts
    /// the result in place of the original. `crop.source` must be the
    /// track's displayed size.
    static func replace(_ url: URL, croppingTo crop: VideoCrop, track: VideoTrack) async throws {
        let asset = AVURLAsset(url: url)
        guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MovieFileError.noVideoTrack
        }
        let duration = try await asset.load(.duration)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)
        layer.setTransform(
            crop.transform(forTrackWith: track.preferredTransform, naturalSize: track.naturalSize),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: crop.output.width, height: crop.output.height)
        let framesPerSecond = track.nominalFrameRate > 0 ? Int32(track.nominalFrameRate.rounded()) : 30
        composition.frameDuration = CMTime(value: 1, timescale: framesPerSecond)
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw MovieFileError.cannotExport
        }
        export.videoComposition = composition
        let cropped = url.deletingLastPathComponent()
            .appending(path: ".\(url.deletingPathExtension().lastPathComponent)-cropping.mov")
        try? FileManager.default.removeItem(at: cropped)
        do {
            try await export.export(to: cropped, as: .mov)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: cropped)
        } catch {
            try? FileManager.default.removeItem(at: cropped)
            throw error
        }
    }
}
