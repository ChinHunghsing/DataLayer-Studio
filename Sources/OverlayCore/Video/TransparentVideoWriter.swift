import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum OverlayVideoCodec: String, CaseIterable, Hashable, Identifiable, Sendable {
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
    public var cancellationHandler: (() -> Bool)?

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
        progressHandler: ((Int, Int) -> Void)? = nil,
        cancellationHandler: (() -> Bool)? = nil
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
        self.cancellationHandler = cancellationHandler
    }
}

public struct TransparentVideoFrameTiming {
    public static let preferredTimescale: CMTimeScale = 600_000

    public let framesPerSecond: Double
    public let duration: TimeInterval
    public let frameCount: Int
    public let frameCountWasClamped: Bool

    public init(framesPerSecond: Double, duration: TimeInterval) {
        let fps = framesPerSecond.isFinite ? framesPerSecond : 1
        let duration = duration.isFinite ? duration : 0
        self.framesPerSecond = max(1, fps)
        self.duration = max(0, duration)

        let rawFrameCount = ceil(self.duration * self.framesPerSecond)
        if rawFrameCount.isFinite, rawFrameCount < Double(Int.max) {
            self.frameCount = max(1, Int(rawFrameCount))
            self.frameCountWasClamped = false
        } else if self.duration <= 0 {
            self.frameCount = 1
            self.frameCountWasClamped = false
        } else {
            self.frameCount = Int.max
            self.frameCountWasClamped = true
        }
    }

    public func presentationTime(for frameIndex: Int) -> CMTime {
        let safeFrameIndex = max(0, frameIndex)
        return CMTime(
            seconds: Double(safeFrameIndex) / framesPerSecond,
            preferredTimescale: Self.preferredTimescale
        )
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
        if config.cancellationHandler?() == true {
            throw OverlayVideoError.cancelled
        }

        let temporaryOutputURL = makeTemporaryOutputURL()
        removePartialOutput(at: temporaryOutputURL)

        do {
            try write(to: temporaryOutputURL)
            try installCompletedOutput(from: temporaryOutputURL)
        } catch {
            removePartialOutput(at: temporaryOutputURL)
            throw error
        }
    }

    private func write(to temporaryOutputURL: URL) throws {
        try validateConfiguration()

        let width = config.width
        let height = config.height
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        )
        let fps = timing.framesPerSecond
        let frameCount = timing.frameCount
        guard !timing.frameCountWasClamped else {
            throw OverlayVideoError.invalidConfiguration(
                "Output duration and frame rate produce too many frames. Lower the duration or frame rate."
            )
        }
        let encoderFrameRate = try encoderFrameRateValue(fps)

        let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        let settings = Self.videoOutputSettings(
            width: width,
            height: height,
            codec: config.codec,
            averageBitRate: config.averageBitRate,
            encoderFrameRate: encoderFrameRate,
            hardwareProfile: .current
        )

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder(
                "This macOS installation cannot add a \(config.codec.displayName) video writer input."
            )
        }
        writer.add(input)

        let sourceAttributes = OverlayPixelBufferAttributes.canvas(width: width, height: height)
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

        let renderQueue = DispatchQueue(label: "run.libo.overlay.video-writer")
        let renderFinished = DispatchSemaphore(value: 0)
        let codec = config.codec
        let progressHandler = config.progressHandler
        let cancellationHandler = config.cancellationHandler
        var frameIndex = 0
        var renderError: Error?
        var didFinishInput = false

        input.requestMediaDataWhenReady(on: renderQueue) {
            while input.isReadyForMoreMediaData, frameIndex < frameCount, renderError == nil {
                do {
                    if cancellationHandler?() == true {
                        throw OverlayVideoError.cancelled
                    }

                    guard let pool = adaptor.pixelBufferPool else {
                        throw OverlayVideoError.cannotCreatePixelBuffer
                    }
                    var pixelBuffer: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                    guard status == kCVReturnSuccess, let pixelBuffer else {
                        throw OverlayVideoError.cannotCreatePixelBuffer
                    }

                    let presentationTime = timing.presentationTime(for: frameIndex)
                    let videoTime = CMTimeGetSeconds(presentationTime)
                    try renderer.render(videoTime: videoTime, into: pixelBuffer)
                    try Self.prepareAlphaForEncoding(on: pixelBuffer, codec: codec)
                    guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw OverlayVideoError.writerFailed(self.describe(error: writer.error, codec: codec))
                    }

                    frameIndex += 1
                    if frameIndex == frameCount || frameIndex % Int(max(1, fps)) == 0 {
                        progressHandler?(frameIndex, frameCount)
                    }
                } catch {
                    renderError = error
                }
            }

            if (frameIndex >= frameCount || renderError != nil), !didFinishInput {
                didFinishInput = true
                input.markAsFinished()
                renderFinished.signal()
            }
        }
        renderFinished.wait()

        if let renderError {
            writer.cancelWriting()
            throw renderError
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec))
        }
    }

    private func validateConfiguration() throws {
        guard config.width > 0, config.height > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be positive.")
        }
        guard config.width <= 16_384, config.height <= 16_384 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be 16,384 px or smaller.")
        }
        guard config.width % 2 == 0, config.height % 2 == 0 else {
            throw OverlayVideoError.invalidConfiguration("Output width and height must be even pixel values.")
        }
        guard config.framesPerSecond.isFinite, config.framesPerSecond > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output frame rate must be a positive finite number.")
        }
        guard config.duration.isFinite, config.duration > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output duration must be a positive finite number.")
        }
        guard config.averageBitRate > 0 else {
            throw OverlayVideoError.invalidConfiguration("Output bitrate must be positive.")
        }
        guard config.averageBitRate <= 1_000_000_000 else {
            throw OverlayVideoError.invalidConfiguration("Output bitrate must be 1,000,000 kbps or lower.")
        }
        try validateOutputURL()
    }

    static func videoOutputSettings(
        width: Int,
        height: Int,
        codec: OverlayVideoCodec,
        averageBitRate: Int,
        encoderFrameRate: Int,
        hardwareProfile: OverlayHardwareProfile
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        if let encoderSpecification = hardwareEncoderSpecification(
            codec: codec,
            hardwareProfile: hardwareProfile
        ) {
            settings[AVVideoEncoderSpecificationKey] = encoderSpecification
        }

        if codec == .hevcAlpha {
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: averageBitRate,
                AVVideoExpectedSourceFrameRateKey: encoderFrameRate,
                AVVideoMaxKeyFrameIntervalKey: encoderFrameRate,
                AVVideoAllowFrameReorderingKey: false,
                kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_StraightAlpha,
                kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0
            ]
        }

        return settings
    }

    private static func prepareAlphaForEncoding(on pixelBuffer: CVPixelBuffer, codec: OverlayVideoCodec) throws {
        if codec == .hevcAlpha {
            try unpremultiplyAlpha(in: pixelBuffer)
            CVBufferSetAttachment(
                pixelBuffer,
                kCVImageBufferAlphaChannelModeKey,
                kCVImageBufferAlphaChannelMode_StraightAlpha,
                .shouldPropagate
            )
            return
        }

        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
            .shouldPropagate
        )
    }

    private static func unpremultiplyAlpha(in pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<height {
            let rowStart = row * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let alpha = Int(bytes[offset + 3])
                if alpha == 0 {
                    bytes[offset] = 0
                    bytes[offset + 1] = 0
                    bytes[offset + 2] = 0
                } else if alpha < 255 {
                    bytes[offset] = unpremultiplied(bytes[offset], alpha: alpha)
                    bytes[offset + 1] = unpremultiplied(bytes[offset + 1], alpha: alpha)
                    bytes[offset + 2] = unpremultiplied(bytes[offset + 2], alpha: alpha)
                }
            }
        }
    }

    private static func unpremultiplied(_ component: UInt8, alpha: Int) -> UInt8 {
        UInt8(min(255, (Int(component) * 255 + alpha / 2) / alpha))
    }

    private static func hardwareEncoderSpecification(
        codec: OverlayVideoCodec,
        hardwareProfile: OverlayHardwareProfile
    ) -> [String: Any]? {
        if let encoder = hardwareProfile.hardwareEncoder(for: codec) {
            var specification: [String: Any] = [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ]
            if let encoderID = encoder.encoderID {
                specification[kVTVideoEncoderSpecification_EncoderID as String] = encoderID
            }
            if let gpuRegistryID = encoder.gpuRegistryID {
                specification[kVTVideoEncoderSpecification_PreferredEncoderGPURegistryID as String] = NSNumber(value: gpuRegistryID)
            }
            return specification
        }

        if hardwareProfile.isAppleSiliconProcess {
            return [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
            ]
        }

        return nil
    }

    private func validateOutputURL() throws {
        let fileManager = FileManager.default
        let directory = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw OverlayVideoError.invalidConfiguration("Output directory does not exist: \(directory.path)")
        }

        var outputIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &outputIsDirectory),
           outputIsDirectory.boolValue {
            throw OverlayVideoError.invalidConfiguration("Output path must be a file, not a directory: \(outputURL.path)")
        }
    }

    private func encoderFrameRateValue(_ framesPerSecond: Double) throws -> Int {
        let rounded = framesPerSecond.rounded()
        guard rounded.isFinite,
              rounded >= 1,
              rounded <= Double(Int.max) else {
            throw OverlayVideoError.invalidConfiguration("Output frame rate is too large for the encoder.")
        }
        return Int(rounded)
    }

    private func makeTemporaryOutputURL() -> URL {
        let directory = outputURL.deletingLastPathComponent()
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let pathExtension = outputURL.pathExtension.isEmpty ? "mov" : outputURL.pathExtension
        return directory
            .appendingPathComponent(".\(baseName).\(UUID().uuidString).tmp")
            .appendingPathExtension(pathExtension)
    }

    private func installCompletedOutput(from temporaryOutputURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                if !isMissingFileError(error) {
                    throw error
                }
            }
        }

        try fileManager.moveItem(at: temporaryOutputURL, to: outputURL)
    }

    private func removePartialOutput(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(POSIXErrorCode.ENOENT.rawValue) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlyingError.domain == NSPOSIXErrorDomain,
           underlyingError.code == Int(POSIXErrorCode.ENOENT.rawValue) {
            return true
        }
        return false
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
