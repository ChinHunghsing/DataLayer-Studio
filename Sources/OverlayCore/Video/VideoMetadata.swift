import AVFoundation
import CoreGraphics
import Foundation

public struct VideoMetadata {
    public var size: CGSize
    public var duration: TimeInterval
    public var framesPerSecond: Double
    public var bitRateBitsPerSecond: Double?

    public init(size: CGSize, duration: TimeInterval, framesPerSecond: Double, bitRateBitsPerSecond: Double? = nil) {
        self.size = size
        self.duration = duration
        self.framesPerSecond = framesPerSecond
        self.bitRateBitsPerSecond = bitRateBitsPerSecond
    }

    public static func load(from url: URL) throws -> VideoMetadata {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = VideoMetadataResultBox()

        Task.detached {
            do {
                resultBox.set(.success(try await loadAsync(from: url)))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result = resultBox.result else {
            throw OverlayVideoError.unreadableVideo("Could not load video metadata from \(url.path).")
        }
        return try result.get()
    }

    public static func loadAsync(from url: URL) async throws -> VideoMetadata {
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
        let estimatedDataRate = try? await track.load(.estimatedDataRate)
        let trackBitRate = estimatedDataRate.flatMap { rate -> Double? in
            let bitRate = Double(rate)
            return bitRate.isFinite && bitRate > 0 ? bitRate : nil
        }
        return VideoMetadata(
            size: size,
            duration: duration,
            framesPerSecond: fps,
            bitRateBitsPerSecond: trackBitRate ?? fileBitRateBitsPerSecond(for: url, duration: duration)
        )
    }

    private static func fileBitRateBitsPerSecond(for url: URL, duration: TimeInterval) -> Double? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0 else { return nil }
        let bitRate = Double(fileSize) * 8 / duration
        return bitRate.isFinite && bitRate > 0 ? bitRate : nil
    }
}

private final class VideoMetadataResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<VideoMetadata, Error>?

    var result: Result<VideoMetadata, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func set(_ result: Result<VideoMetadata, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}

public enum OverlayVideoError: Error, CustomStringConvertible, LocalizedError {
    case unreadableVideo(String)
    case cannotCreatePixelBuffer
    case cannotCreateBitmapContext
    case cannotStartWriter(String)
    case writerFailed(String)
    case unsupportedEncoder(String)
    case invalidConfiguration(String)
    case cancelled

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
        case let .invalidConfiguration(message):
            return message
        case .cancelled:
            return "Video export was cancelled."
        }
    }

    public var errorDescription: String? {
        description
    }
}
