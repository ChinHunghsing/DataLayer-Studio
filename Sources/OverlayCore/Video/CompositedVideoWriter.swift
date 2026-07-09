import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import VideoToolbox

public struct CompositedVideoWriterConfig {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var averageBitRate: Int
    public var timeSync: TelemetryTimeSync
    public var codec: OverlayVideoCodec
    public var overlayLayout: OverlayLayout
    public var distanceUnit: OverlayDistanceUnit
    public var activityTrim: ActivityTrim
    public var progressHandler: ((Int, Int) -> Void)?
    public var cancellationHandler: (() -> Bool)?
    public var diagnosticsHandler: ((String) -> Void)?

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Double,
        startTime: TimeInterval = 0,
        duration: TimeInterval,
        averageBitRate: Int = 12_000_000,
        timeSync: TelemetryTimeSync = .identity,
        codec: OverlayVideoCodec = .hevc,
        overlayLayout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers,
        activityTrim: ActivityTrim = .none,
        progressHandler: ((Int, Int) -> Void)? = nil,
        cancellationHandler: (() -> Bool)? = nil,
        diagnosticsHandler: ((String) -> Void)? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.startTime = startTime
        self.duration = duration
        self.averageBitRate = averageBitRate
        self.timeSync = timeSync
        self.codec = codec
        self.overlayLayout = overlayLayout
        self.distanceUnit = distanceUnit
        self.activityTrim = activityTrim
        self.progressHandler = progressHandler
        self.cancellationHandler = cancellationHandler
        self.diagnosticsHandler = diagnosticsHandler
    }
}

public final class CompositedVideoWriter {
    private static let temporaryFilePrefix = "DataLayerStudio-"

    private let outputURL: URL
    private let sourceAsset: AVAsset?
    private let sourceDescription: String
    private let sourceVideoRanges: [CMTimeRange]?
    private let series: TelemetrySeries?
    private let config: CompositedVideoWriterConfig
    private let overlayStartTime: TimeInterval
    private let renderOverlay: ((TimeInterval, CVPixelBuffer) throws -> Void)?

    public init(outputURL: URL, sourceVideoURL: URL, series: TelemetrySeries, config: CompositedVideoWriterConfig) {
        self.outputURL = outputURL
        self.sourceAsset = AVURLAsset(url: sourceVideoURL)
        self.sourceDescription = sourceVideoURL.path
        self.sourceVideoRanges = nil
        self.series = series
        self.config = config
        self.overlayStartTime = config.startTime
        self.renderOverlay = nil
    }

    init(
        outputURL: URL,
        sourceVideoURL: URL,
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void
    ) {
        self.outputURL = outputURL
        self.sourceAsset = AVURLAsset(url: sourceVideoURL)
        self.sourceDescription = sourceVideoURL.path
        self.sourceVideoRanges = nil
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
    }

    init(
        outputURL: URL,
        sourceAsset: AVAsset,
        sourceDescription: String,
        sourceVideoRanges: [CMTimeRange]? = nil,
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void
    ) {
        self.outputURL = outputURL
        self.sourceAsset = sourceAsset
        self.sourceDescription = sourceDescription
        self.sourceVideoRanges = sourceVideoRanges
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
    }

    init(
        outputURL: URL,
        config: CompositedVideoWriterConfig,
        overlayStartTime: TimeInterval,
        renderOverlay: @escaping (TimeInterval, CVPixelBuffer) throws -> Void
    ) {
        self.outputURL = outputURL
        self.sourceAsset = nil
        self.sourceDescription = "black timeline canvas"
        self.sourceVideoRanges = nil
        self.series = nil
        self.config = config
        self.overlayStartTime = overlayStartTime
        self.renderOverlay = renderOverlay
    }

    public func write() throws {
        if config.cancellationHandler?() == true {
            throw OverlayVideoError.cancelled
        }

        TransparentVideoWriter.removeStaleTemporaryOutputs()
        let videoOnlyURL = makeTemporaryOutputURL(tag: "video")
        let finalURL = makeTemporaryOutputURL(tag: "final")
        removePartialOutput(at: videoOnlyURL)
        removePartialOutput(at: finalURL)

        do {
            try writeVideoOnly(to: videoOnlyURL)
            if let sourceAsset, hasAudioTrack(in: sourceAsset) {
                try muxOriginalAudio(videoURL: videoOnlyURL, outputURL: finalURL)
                try installCompletedOutput(from: finalURL)
            } else {
                try installCompletedOutput(from: videoOnlyURL)
            }
        } catch {
            removePartialOutput(at: videoOnlyURL)
            removePartialOutput(at: finalURL)
            throw error
        }
        removePartialOutput(at: videoOnlyURL)
        removePartialOutput(at: finalURL)
    }

    private func writeVideoOnly(to temporaryOutputURL: URL) throws {
        try validateConfiguration()

        let width = config.width
        let height = config.height
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        )
        guard !timing.frameCountWasClamped else {
            throw OverlayVideoError.invalidConfiguration(
                "Output duration and frame rate produce too many frames. Lower the duration or frame rate."
            )
        }
        let encoderFrameRate = try encoderFrameRateValue(timing.framesPerSecond)

        let trimStartTime = CMTime(seconds: config.startTime, preferredTimescale: timing.mediaTimeScale)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let reader: AVAssetReader?
        let readerOutput: AVAssetReaderOutput?
        let sourceTransform: CGAffineTransform
        if let sourceAsset {
            guard let videoTrack = sourceAsset.tracks(withMediaType: .video).first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(sourceDescription).")
            }
            let newReader = try AVAssetReader(asset: sourceAsset)
            newReader.timeRange = CMTimeRange(start: trimStartTime, duration: timing.outputDuration)
            let newOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: readerSettings
            )
            sourceTransform = makeSourceTransform(track: videoTrack, width: width, height: height)
            newOutput.alwaysCopiesSampleData = false
            guard newReader.canAdd(newOutput) else {
                throw OverlayVideoError.unreadableVideo("Could not read composited video frames from \(sourceDescription).")
            }
            newReader.add(newOutput)
            reader = newReader
            readerOutput = newOutput
        } else {
            reader = nil
            readerOutput = nil
            sourceTransform = .identity
        }

        let hardwareProfile = OverlayHardwareProfile.current
        let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        writer.movieTimeScale = timing.mediaTimeScale
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(
                width: width,
                height: height,
                codec: config.codec,
                averageBitRate: config.averageBitRate,
                encoderFrameRate: encoderFrameRate,
                expectedSourceFrameRate: timing.framesPerSecond,
                hardwareProfile: hardwareProfile
            )
        )
        input.mediaTimeScale = timing.mediaTimeScale
        input.expectsMediaDataInRealTime = false
        input.performsMultiPassEncodingIfSupported = false
        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder(
                "This macOS installation cannot add a \(config.codec.displayName) video writer input."
            )
        }
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: OverlayPixelBufferAttributes.canvas(width: width, height: height)
        )

        if let reader, !reader.startReading() {
            throw OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Could not start reading source video.")
        }
        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(describe(error: writer.error, codec: config.codec))
        }
        writer.startSession(atSourceTime: .zero)

        let renderer = series.map {
            OverlayRenderer(
                series: $0,
                config: OverlayRenderConfig(
                    size: CGSize(width: width, height: height),
                    timeSync: config.timeSync,
                    layout: config.overlayLayout,
                    distanceUnit: config.distanceUnit,
                    activityTrim: config.activityTrim
                )
            )
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ciContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
        let overlayPool = try TransparentVideoWriter.makePixelBufferPool(width: width, height: height, minimumBufferCount: 2)
        let outputBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: outputBounds)

        let renderQueue = DispatchQueue(label: "run.libo.overlay.composited-writer")
        let writeFinished = DispatchSemaphore(value: 0)
        let codec = config.codec
        let progressHandler = config.progressHandler
        let cancellationHandler = config.cancellationHandler
        let sparseVideoRanges = sourceVideoRanges
        let frameCount = timing.frameCount
        var frameIndex = 0
        var writeError: Error?
        var sourceExhausted = false
        var didFinishInput = false
        var currentSourceSample: CMSampleBuffer?
        var pendingSourceSample: CMSampleBuffer?
        var sparseRangeIndex = 0

        input.requestMediaDataWhenReady(on: renderQueue) {
            while input.isReadyForMoreMediaData,
                  frameIndex < frameCount,
                  writeError == nil,
                  !sourceExhausted {
                do {
                    var didReadFrame = false
                    try autoreleasepool {
                        if cancellationHandler?() == true {
                            throw OverlayVideoError.cancelled
                        }

                        guard let pool = adaptor.pixelBufferPool else {
                            throw OverlayVideoError.cannotCreatePixelBuffer
                        }
                        let presentationTime = timing.presentationTime(for: frameIndex)
                        let sourceTime = CMTimeAdd(trimStartTime, presentationTime)
                        var sourceImage = background
                        if let readerOutput, let sparseVideoRanges {
                            let tolerance = CMTimeMultiplyByFloat64(timing.frameDuration, multiplier: 0.5)
                            let latestAcceptedTime = CMTimeAdd(sourceTime, tolerance)
                            while true {
                                if pendingSourceSample == nil {
                                    pendingSourceSample = readerOutput.copyNextSampleBuffer()
                                }
                                guard let sample = pendingSourceSample else { break }
                                let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample)
                                guard sampleTime <= latestAcceptedTime else { break }
                                currentSourceSample = sample
                                pendingSourceSample = nil
                            }
                            while sparseRangeIndex < sparseVideoRanges.count,
                                  sourceTime >= CMTimeRangeGetEnd(sparseVideoRanges[sparseRangeIndex]) {
                                sparseRangeIndex += 1
                            }
                            if sparseRangeIndex < sparseVideoRanges.count,
                               CMTimeRangeContainsTime(sparseVideoRanges[sparseRangeIndex], time: sourceTime),
                               let currentSourceSample,
                               let sourceBuffer = CMSampleBufferGetImageBuffer(currentSourceSample) {
                                sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
                                    .transformed(by: sourceTransform)
                                    .composited(over: background)
                            }
                        } else if let readerOutput {
                            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { return }
                            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                                throw OverlayVideoError.cannotCreatePixelBuffer
                            }
                            sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
                                .transformed(by: sourceTransform)
                                .composited(over: background)
                        }
                        didReadFrame = true

                        let outputBuffer = try TransparentVideoWriter.makePixelBuffer(from: pool)
                        let overlayBuffer = try TransparentVideoWriter.makePixelBuffer(from: overlayPool)
                        let overlayTime = self.overlayStartTime + CMTimeGetSeconds(presentationTime)

                        if let renderOverlay = self.renderOverlay {
                            try renderOverlay(overlayTime, overlayBuffer)
                        } else if let renderer {
                            try renderer.render(videoTime: overlayTime, into: overlayBuffer)
                        }
                        let composed = CIImage(cvPixelBuffer: overlayBuffer)
                            .composited(over: sourceImage)
                        ciContext.render(
                            composed,
                            to: outputBuffer,
                            bounds: outputBounds,
                            colorSpace: colorSpace
                        )

                        guard try TransparentVideoWriter.appendPixelBuffer(
                            outputBuffer,
                            to: input,
                            at: presentationTime,
                            duration: timing.frameDuration
                        ) else {
                            throw OverlayVideoError.writerFailed(self.describe(error: writer.error, codec: codec))
                        }

                        frameIndex += 1
                        if frameIndex == frameCount || frameIndex % Int(max(1, timing.framesPerSecond)) == 0 {
                            progressHandler?(frameIndex, frameCount)
                        }
                    }
                    if !didReadFrame {
                        sourceExhausted = true
                    }
                } catch {
                    writeError = error
                }
            }

            if (frameIndex >= frameCount || writeError != nil || sourceExhausted), !didFinishInput {
                didFinishInput = true
                if writeError == nil {
                    writer.endSession(atSourceTime: timing.outputDuration)
                }
                input.markAsFinished()
                writeFinished.signal()
            }
        }
        writeFinished.wait()

        if let writeError {
            reader?.cancelReading()
            writer.cancelWriting()
            throw writeError
        }
        if let reader, reader.status == .failed {
            writer.cancelWriting()
            throw OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Source video reading failed.")
        }
        guard frameIndex > 0 else {
            writer.cancelWriting()
            throw OverlayVideoError.unreadableVideo("No video frames could be read from \(sourceDescription).")
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
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
        guard config.startTime.isFinite, config.startTime >= 0 else {
            throw OverlayVideoError.invalidConfiguration("Output start time must be a non-negative finite number.")
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
        guard config.codec.exportMode == .video else {
            throw OverlayVideoError.invalidConfiguration("\(config.codec.displayName) cannot be used for composited video export.")
        }
        try validateOutputURL()
    }

    private func makeSourceTransform(track: AVAssetTrack, width: Int, height: Int) -> CGAffineTransform {
        let outputSize = CGSize(width: width, height: height)
        let naturalSize = track.naturalSize
        let preferredTransform = track.preferredTransform
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let scale = min(outputSize.width / max(1, displaySize.width), outputSize.height / max(1, displaySize.height))
        let x = -transformedRect.minX * scale + (outputSize.width - displaySize.width * scale) / 2
        let y = -transformedRect.minY * scale + (outputSize.height - displaySize.height * scale) / 2
        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
        return transform
    }

    private func muxOriginalAudio(videoURL: URL, outputURL: URL) throws {
        let videoAsset = AVURLAsset(url: videoURL)
        guard let sourceAsset else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }
        let audioTracks = sourceAsset.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            throw OverlayVideoError.writerFailed("Could not find rendered video track before audio muxing.")
        }

        let composition = AVMutableComposition()
        let duration = TransparentVideoFrameTiming(
            framesPerSecond: config.framesPerSecond,
            duration: config.duration
        ).outputDuration
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        let sourceAudioRange = CMTimeRange(
            start: CMTime(seconds: config.startTime, preferredTimescale: duration.timescale),
            duration: duration
        )

        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OverlayVideoError.writerFailed("Could not create muxed video track.")
        }
        try compositionVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        for audioTrack in audioTracks {
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            let clippedAudioRange = CMTimeRangeGetIntersection(audioTrack.timeRange, otherRange: sourceAudioRange)
            guard clippedAudioRange.duration > .zero else { continue }
            let destinationStart = CMTimeSubtract(clippedAudioRange.start, sourceAudioRange.start)
            try compositionAudio.insertTimeRange(
                clippedAudioRange,
                of: audioTrack,
                at: destinationStart
            )
        }

        do {
            try exportComposition(
                composition,
                outputURL: outputURL,
                timeRange: timeRange,
                presetName: AVAssetExportPresetPassthrough
            )
        } catch {
            config.diagnosticsHandler?(
                "Audio passthrough mux failed (\(error.localizedDescription)); re-exporting with highest quality preset, video will be re-encoded."
            )
            removePartialOutput(at: outputURL)
            try exportComposition(
                composition,
                outputURL: outputURL,
                timeRange: timeRange,
                presetName: AVAssetExportPresetHighestQuality
            )
        }
    }

    private func exportComposition(
        _ composition: AVComposition,
        outputURL: URL,
        timeRange: CMTimeRange,
        presetName: String
    ) throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw OverlayVideoError.writerFailed("Could not create audio mux export session.")
        }
        removePartialOutput(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously { semaphore.signal() }
        semaphore.wait()

        guard exportSession.status == .completed else {
            throw OverlayVideoError.writerFailed(describe(error: exportSession.error, fallback: "Audio muxing failed."))
        }
    }

    private func hasAudioTrack(in asset: AVAsset) -> Bool {
        !asset.tracks(withMediaType: .audio).isEmpty
    }

    private func videoOutputSettings(
        width: Int,
        height: Int,
        codec: OverlayVideoCodec,
        averageBitRate: Int,
        encoderFrameRate: Int,
        expectedSourceFrameRate: Double,
        hardwareProfile: OverlayHardwareProfile
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if let encoderSpecification = TransparentVideoWriter.hardwareEncoderSpecification(
            codec: codec,
            hardwareProfile: hardwareProfile
        ) {
            #if os(macOS)
            settings[AVVideoEncoderSpecificationKey] = encoderSpecification
            #endif
        }
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: averageBitRate,
            AVVideoExpectedSourceFrameRateKey: expectedSourceFrameRate,
            AVVideoMaxKeyFrameIntervalKey: encoderFrameRate,
            AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_RealTime as String: true
        ]
        // 软件编码器（如 iOS 模拟器）不接受该加速提示属性，传入会让 AVAssetWriterInput 直接抛异常。
        if hardwareProfile.canUseHardwareEncoder(for: codec) {
            compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
        }
        settings[AVVideoCompressionPropertiesKey] = compressionProperties
        return settings
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

    private func makeTemporaryOutputURL(tag: String) -> URL {
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let pathExtension = outputURL.pathExtension.isEmpty ? "mov" : outputURL.pathExtension
        let safeBaseName = baseName.isEmpty ? "datalayer-video" : baseName
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.temporaryFilePrefix)\(ProcessInfo.processInfo.processIdentifier)-\(tag)-\(safeBaseName)-\(UUID().uuidString)")
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

    private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
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
        "\(describe(error: error, fallback: "Unknown writer failure")) while using \(codec.displayName)."
    }

    private func describe(error: Error?, fallback: String) -> String {
        guard let error else {
            return fallback
        }
        let nsError = error as NSError
        if nsError.userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription) \(nsError.userInfo)"
    }
}
