import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
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
    private static let temporaryFilePrefix = "DataLayerStudio-"

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

        Self.removeStaleTemporaryOutputs()
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

    public static func removeStaleTemporaryOutputs() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where shouldRemoveTemporaryOutput(url) {
            try? fileManager.removeItem(at: url)
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

        let hardwareProfile = OverlayHardwareProfile.current
        let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        let settings = Self.videoOutputSettings(
            width: width,
            height: height,
            codec: config.codec,
            averageBitRate: config.averageBitRate,
            encoderFrameRate: encoderFrameRate,
            hardwareProfile: hardwareProfile
        )

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.performsMultiPassEncodingIfSupported = false
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
        let alphaContext = codec == .hevcAlpha ? OverlayCIContextFactory.makeContext(profile: hardwareProfile) : nil
        let alphaColorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaRenderPool = codec == .hevcAlpha
            ? try Self.makePixelBufferPool(width: width, height: height, minimumBufferCount: 2)
            : nil
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
                    let appendBuffer = try Self.makePixelBuffer(from: pool)
                    let renderBuffer: CVPixelBuffer
                    if let alphaRenderPool {
                        renderBuffer = try Self.makePixelBuffer(from: alphaRenderPool)
                    } else {
                        renderBuffer = appendBuffer
                    }

                    let presentationTime = timing.presentationTime(for: frameIndex)
                    let videoTime = CMTimeGetSeconds(presentationTime)
                    try renderer.render(videoTime: videoTime, into: renderBuffer)
                    if let alphaContext {
                        Self.prepareHEVCAlphaForEncoding(
                            from: renderBuffer,
                            to: appendBuffer,
                            context: alphaContext,
                            colorSpace: alphaColorSpace
                        )
                    } else {
                        Self.preparePremultipliedAlphaForEncoding(on: appendBuffer)
                    }
                    guard adaptor.append(appendBuffer, withPresentationTime: presentationTime) else {
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
                kVTCompressionPropertyKey_RealTime as String: true,
                kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true,
                kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_StraightAlpha,
                kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0
            ]
        }

        return settings
    }

    private static func prepareHEVCAlphaForEncoding(
        from source: CVPixelBuffer,
        to destination: CVPixelBuffer,
        context: CIContext,
        colorSpace: CGColorSpace
    ) {
        let width = CVPixelBufferGetWidth(destination)
        let height = CVPixelBufferGetHeight(destination)
        let image = CIImage(cvPixelBuffer: source).unpremultiplyingAlpha()
        context.render(image, to: destination, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
        CVBufferSetAttachment(
            destination,
            kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_StraightAlpha,
            .shouldPropagate
        )
    }

    private static func preparePremultipliedAlphaForEncoding(on pixelBuffer: CVPixelBuffer) {
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
            .shouldPropagate
        )
    }

    private static func makePixelBufferPool(width: Int, height: Int, minimumBufferCount: Int) throws -> CVPixelBufferPool {
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: minimumBufferCount]
        let attributes = OverlayPixelBufferAttributes.canvas(width: width, height: height)
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pool
    }

    private static func makePixelBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
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

    func makeTemporaryOutputURL() -> URL {
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let pathExtension = outputURL.pathExtension.isEmpty ? "mov" : outputURL.pathExtension
        let safeBaseName = baseName.isEmpty ? "datalayer-overlay" : baseName
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.temporaryFilePrefix)\(ProcessInfo.processInfo.processIdentifier)-\(safeBaseName)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func shouldRemoveTemporaryOutput(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix(temporaryFilePrefix) else { return false }

        let remainder = name.dropFirst(temporaryFilePrefix.count)
        guard let separator = remainder.firstIndex(of: "-"),
              let pid = Int32(remainder[..<separator]) else {
            return true
        }
        return !isProcessRunning(pid)
    }

    private static func isProcessRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if pid == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
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
