import AVFoundation
import CoreGraphics
import Foundation

public struct VideoMetadata {
    public var size: CGSize
    public var duration: TimeInterval
    public var framesPerSecond: Double

    public init(size: CGSize, duration: TimeInterval, framesPerSecond: Double) {
        self.size = size
        self.duration = duration
        self.framesPerSecond = framesPerSecond
    }

    public static func load(from url: URL) throws -> VideoMetadata {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<VideoMetadata, Error>?

        Task {
            do {
                result = .success(try await loadAsync(from: url))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try result!.get()
    }

    private static func loadAsync(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)
        guard duration.isFinite, duration > 0 else {
            throw OverlayVideoError.unreadableVideo("Could not read a positive duration from \(url.path).")
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw OverlayVideoError.unreadableVideo("No video track found in \(url.path).")
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
        return VideoMetadata(size: size, duration: duration, framesPerSecond: fps)
    }
}

public enum OverlayVideoError: Error, CustomStringConvertible {
    case unreadableVideo(String)
    case cannotCreatePixelBuffer
    case cannotCreateBitmapContext
    case cannotStartWriter(String)
    case writerFailed(String)
    case unsupportedEncoder(String)

    public var description: String {
        switch self {
        case let .unreadableVideo(message):
            return message
        case .cannotCreatePixelBuffer:
            return "Could not create a 32-bit BGRA pixel buffer."
        case .cannotCreateBitmapContext:
            return "Could not create a bitmap context for overlay rendering."
        case let .cannotStartWriter(message):
            return "Could not start AVAssetWriter: \(message)"
        case let .writerFailed(message):
            return "AVAssetWriter failed: \(message)"
        case let .unsupportedEncoder(message):
            return message
        }
    }
}
