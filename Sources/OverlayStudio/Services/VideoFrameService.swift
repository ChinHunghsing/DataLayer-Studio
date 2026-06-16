import AppKit
import AVFoundation
import Foundation

final class VideoFrameService {
    func frameImage(videoURL: URL, time: TimeInterval) throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let cgImage = try generator.copyCGImage(
            at: CMTime(seconds: max(0, time), preferredTimescale: 600),
            actualTime: nil
        )
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

