import AppKit
import AVFoundation
import Foundation

final class VideoFrameService {
    private let lock = NSLock()
    private let frameQueue = DispatchQueue(label: "run.libo.overlay-studio.video-frame-service", qos: .userInitiated)
    private var cachedVideoURL: URL?
    private var cachedGenerator: AVAssetImageGenerator?
    private var latestFrameRequestID = 0

    func clearCache() {
        lock.lock()
        defer { lock.unlock() }

        latestFrameRequestID += 1
        cachedGenerator?.cancelAllCGImageGeneration()
        cachedVideoURL = nil
        cachedGenerator = nil
    }

    func frameImage(videoURL: URL, time: TimeInterval) throws -> NSImage {
        let requestID = nextFrameRequestID()
        let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        let cgImage: CGImage = try frameQueue.sync { () throws -> CGImage in
            guard isLatestFrameRequest(requestID) else {
                throw CancellationError()
            }

            let generator = generator(for: videoURL)
            return try generator.copyCGImage(
                at: requestedTime,
                actualTime: nil
            )
        }
        guard isLatestFrameRequest(requestID) else {
            throw CancellationError()
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func nextFrameRequestID() -> Int {
        lock.lock()
        defer { lock.unlock() }

        latestFrameRequestID += 1
        return latestFrameRequestID
    }

    private func isLatestFrameRequest(_ requestID: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return requestID == latestFrameRequestID
    }

    private func generator(for videoURL: URL) -> AVAssetImageGenerator {
        lock.lock()
        defer { lock.unlock() }

        if cachedVideoURL == videoURL, let cachedGenerator {
            return cachedGenerator
        }

        let asset = AVURLAsset(url: videoURL)
        let newGenerator = AVAssetImageGenerator(asset: asset)
        newGenerator.appliesPreferredTrackTransform = true
        newGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        newGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        cachedVideoURL = videoURL
        cachedGenerator = newGenerator
        return newGenerator
    }
}
