@preconcurrency import AVFoundation
import CoreMedia
import Foundation

enum ConversionError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "This file does not contain a video track."
        case .exportFailed(let message):
            return message
        case .cancelled:
            return "Conversion was cancelled."
        }
    }
}

private final class UncheckedSession: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

actor VideoConverter {
    func convert(
        source: URL,
        output: URL,
        settings: ConvertSettings,
        screenSize: CGSize,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let oriented = naturalSize.applying(transform)
        let sourceSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))

        let renderSize = outputSize(
            source: sourceSize,
            screen: screenSize,
            maxLongEdge: settings.quality.maxLongEdge
        )

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ConversionError.exportFailed("Could not build the video composition.")
        }

        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

        if !settings.muteAudio, let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            if let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try? compositionAudio.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: settings.quality.framesPerSecond)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
        layer.setTransform(
            fillOrFitTransform(
                sourceSize: sourceSize,
                preferredTransform: transform,
                renderSize: renderSize,
                fit: settings.fit
            ),
            at: .zero
        )
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        let preset = AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ConversionError.exportFailed("Video export is not available on this Mac.")
        }

        session.outputURL = output
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = false
        session.metadata = [
            makeMetadata(key: AVMetadataKey.commonKeyTitle, value: "MacPaper Wallpaper"),
            makeMetadata(key: AVMetadataKey.commonKeySoftware, value: "MacPaper")
        ]

        try await export(session, progress: progress)
        return output
    }

    private func export(_ session: AVAssetExportSession, progress: @escaping (Double) -> Void) async throws {
        let box = UncheckedSession(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: 0.15)
            timer.setEventHandler {
                progress(Double(box.session.progress))
            }
            timer.resume()

            box.session.exportAsynchronously {
                timer.cancel()
                switch box.session.status {
                case .completed:
                    progress(1)
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ConversionError.cancelled)
                default:
                    let message = box.session.error?.localizedDescription ?? "The video could not be encoded."
                    continuation.resume(throwing: ConversionError.exportFailed(message))
                }
            }
        }
    }

    private func outputSize(source: CGSize, screen: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let target = screen.width > 0 && screen.height > 0 ? screen : source
        let sourceLong = max(target.width, target.height)
        let scale = min(1, maxLongEdge / max(sourceLong, 1))
        var width = (target.width * scale).rounded()
        var height = (target.height * scale).rounded()
        if Int(width) % 2 != 0 { width -= 1 }
        if Int(height) % 2 != 0 { height -= 1 }
        return CGSize(width: max(width, 2), height: max(height, 2))
    }

    private func fillOrFitTransform(
        sourceSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize,
        fit: ConvertSettings.Fit
    ) -> CGAffineTransform {
        var transform = preferredTransform
        let oriented = sourceSize

        let scaleX = renderSize.width / max(oriented.width, 1)
        let scaleY = renderSize.height / max(oriented.height, 1)
        let scale = fit == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)

        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let scaled = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        let tx = (renderSize.width - scaled.width) / 2
        let ty = (renderSize.height - scaled.height) / 2
        transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))
        return transform
    }

    private func makeMetadata(key: AVMetadataKey, value: String) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key as NSString
        item.value = value as NSString
        return item
    }
}
