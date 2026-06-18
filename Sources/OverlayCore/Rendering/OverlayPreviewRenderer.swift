import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public enum OverlayPreviewError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidPreviewSize
    case cannotCreatePreviewImage

    public var description: String {
        switch self {
        case .invalidPreviewSize:
            return "Preview size must be finite, positive, and no larger than 16,384 px per side."
        case .cannotCreatePreviewImage:
            return "Could not create an overlay preview image."
        }
    }

    public var errorDescription: String? {
        description
    }
}

public final class OverlayPreviewRenderer {
    private let hardwareProfile: OverlayHardwareProfile
    private let context: CIContext
    private let pixelBufferPoolLock = NSLock()
    private var pixelBufferPoolSize: PixelBufferPoolSize?
    private var pixelBufferPool: CVPixelBufferPool?

    public init(hardwareProfile: OverlayHardwareProfile = .current) {
        self.hardwareProfile = hardwareProfile
        self.context = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
    }

    public func renderOverlayImage(
        series: TelemetrySeries,
        size: CGSize,
        videoTime: TimeInterval,
        timeSync: TelemetryTimeSync = .identity,
        layout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers
    ) throws -> CGImage {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width <= 16_384,
              size.height <= 16_384 else {
            throw OverlayPreviewError.invalidPreviewSize
        }
        let width = max(2, Int(size.width.rounded()))
        let height = max(2, Int(size.height.rounded()))
        let pixelBuffer = try makePixelBuffer(width: width, height: height)

        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: width, height: height),
                timeSync: timeSync,
                layout: layout,
                distanceUnit: distanceUnit
            )
        )
        try renderer.render(videoTime: videoTime, into: pixelBuffer)

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            throw OverlayPreviewError.cannotCreatePreviewImage
        }
        return cgImage
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let pool = try reusablePixelBufferPool(width: width, height: height)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
    }

    private func reusablePixelBufferPool(width: Int, height: Int) throws -> CVPixelBufferPool {
        let size = PixelBufferPoolSize(width: width, height: height)

        pixelBufferPoolLock.lock()
        defer { pixelBufferPoolLock.unlock() }

        if pixelBufferPoolSize == size, let pixelBufferPool {
            return pixelBufferPool
        }

        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: hardwareProfile.preferredPreviewBufferCount
        ]
        let attributes = OverlayPixelBufferAttributes.canvas(width: width, height: height)

        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &newPool)
        guard status == kCVReturnSuccess, let newPool else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        pixelBufferPoolSize = size
        pixelBufferPool = newPool
        return newPool
    }
}

private struct PixelBufferPoolSize: Equatable {
    var width: Int
    var height: Int
}
