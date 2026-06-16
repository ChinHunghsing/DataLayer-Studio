import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

public enum OverlayVideoCodec: String, CaseIterable, Identifiable {
    case hevcAlpha = "hevc-alpha"
    case proRes4444 = "prores-4444"

    public var id: String { rawValue }

    var avCodecType: AVVideoCodecType {
        switch self {
        case .hevcAlpha:
            return .hevcWithAlpha
        case .proRes4444:
            return .proRes4444
        }
    }

    public var displayName: String {
        switch self {
        case .hevcAlpha:
            return "HEVC/H.265 with alpha"
        case .proRes4444:
            return "Apple ProRes 4444"
        }
    }
}

public struct TransparentVideoWriterConfig {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var duration: TimeInterval
    public var averageBitRate: Int
    public var timeSync: TelemetryTimeSync
    public var codec: OverlayVideoCodec
    public var overlayLayout: OverlayLayout
    public var distanceUnit: OverlayDistanceUnit
    public var progressHandler: ((Int, Int) -> Void)?

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Double,
        duration: TimeInterval,
        averageBitRate: Int = 12_000_000,
        timeSync: TelemetryTimeSync = .identity,
        codec: OverlayVideoCodec = .hevcAlpha,
        overlayLayout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.duration = duration
        self.averageBitRate = averageBitRate
        self.timeSync = timeSync
        self.codec = codec
        self.overlayLayout = overlayLayout
        self.distanceUnit = distanceUnit
        self.progressHandler = progressHandler
    }
}

public final class TransparentVideoWriter {
    private let outputURL: URL
    private let series: TelemetrySeries
    private let config: TransparentVideoWriterConfig

    public init(outputURL: URL, series: TelemetrySeries, config: TransparentVideoWriterConfig) {
        self.outputURL = outputURL
        self.series = series
        self.config = config
    }

    public func write() throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let width = makeEven(config.width)
        let height = makeEven(config.height)
        let fps = max(1, config.framesPerSecond)
        let frameCount = max(1, Int(ceil(config.duration * fps)))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        var settings: [String: Any] = [
            AVVideoCodecKey: config.codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if config.codec == .hevcAlpha {
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: config.averageBitRate,
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
                AVVideoMaxKeyFrameIntervalKey: Int(fps.rounded()),
                AVVideoAllowFrameReorderingKey: false
            ]
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder(
                "This macOS installation cannot add a \(config.codec.displayName) video writer input."
            )
        }
        writer.add(input)

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(describe(error: writer.error, codec: config.codec))
        }
        writer.startSession(atSourceTime: .zero)

        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: width, height: height),
                timeSync: config.timeSync,
                layout: config.overlayLayout,
                distanceUnit: config.distanceUnit
            )
        )

        var frameIndex = 0
        while frameIndex < frameCount {
            if input.isReadyForMoreMediaData {
                guard let pool = adaptor.pixelBufferPool else {
                    throw OverlayVideoError.cannotCreatePixelBuffer
                }
                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard status == kCVReturnSuccess, let pixelBuffer else {
                    throw OverlayVideoError.cannotCreatePixelBuffer
                }

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                let videoTime = CMTimeGetSeconds(presentationTime)
                try renderer.render(videoTime: videoTime, into: pixelBuffer)
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec))
                }

                frameIndex += 1
                if frameIndex == frameCount || frameIndex % Int(max(1, fps)) == 0 {
                    config.progressHandler?(frameIndex, frameCount)
                }
            } else {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec))
        }
    }

    private func makeEven(_ value: Int) -> Int {
        let positive = max(2, value)
        return positive % 2 == 0 ? positive : positive + 1
    }

    private func describe(error: Error?, codec: OverlayVideoCodec) -> String {
        guard let error else { return "Unknown writer failure" }
        let nsError = error as NSError
        var hint = ""
        if codec == .hevcAlpha,
           nsError.domain == AVFoundationErrorDomain,
           nsError.code == AVError.encoderNotFound.rawValue {
            hint = " The system HEVC-with-alpha encoder is unavailable on this Mac; use a Mac/OS combination with that encoder, or pass --codec prores-4444 for an alpha-capable editing intermediate."
        }
        if nsError.userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)\(hint)"
        }
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription) \(nsError.userInfo)\(hint)"
    }
}
