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
    private let context = CIContext(options: nil)

    public init() {}

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
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
    }
}
