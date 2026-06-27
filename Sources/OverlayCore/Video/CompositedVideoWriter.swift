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
        codec: OverlayVideoCodec = .hevc,
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

public final class CompositedVideoWriter {
    private static let temporaryFilePrefix = "DataLayerStudio-"

    private let outputURL: URL
    private let sourceVideoURL: URL
    private let series: TelemetrySeries
    private let config: CompositedVideoWriterConfig

    public init(outputURL: URL, sourceVideoURL: URL, series: TelemetrySeries, config: CompositedVideoWriterConfig) {
        self.outputURL = outputURL
        self.sourceVideoURL = sourceVideoURL
        self.series = series
        self.config = config
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
            if hasAudioTrack(in: sourceVideoURL) {
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

        let asset = AVURLAsset(url: sourceVideoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw OverlayVideoError.unreadableVideo("No video track found in \(sourceVideoURL.path).")
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: OverlayPixelBufferAttributes.canvas(width: width, height: height)
        )
        readerOutput.videoComposition = makeVideoComposition(track: videoTrack, width: width, height: height)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw OverlayVideoError.unreadableVideo("Could not read composited video frames from \(sourceVideoURL.path).")
        }
        reader.add(readerOutput)

        let hardwareProfile = OverlayHardwareProfile.current
        let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(
                width: width,
                height: height,
                codec: config.codec,
                averageBitRate: config.averageBitRate,
                encoderFrameRate: encoderFrameRate,
                hardwareProfile: hardwareProfile
            )
        )
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

        guard reader.startReading() else {
            throw OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Could not start reading source video.")
        }
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
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ciContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
        let overlayPool = try TransparentVideoWriter.makePixelBufferPool(width: width, height: height, minimumBufferCount: 2)
        var frameIndex = 0

        while frameIndex < timing.frameCount, let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if config.cancellationHandler?() == true {
                reader.cancelReading()
                writer.cancelWriting()
                throw OverlayVideoError.cancelled
            }

            try waitUntilReady(input)
            guard let pool = adaptor.pixelBufferPool else {
                throw OverlayVideoError.cannotCreatePixelBuffer
            }
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw OverlayVideoError.cannotCreatePixelBuffer
            }

            let outputBuffer = try TransparentVideoWriter.makePixelBuffer(from: pool)
            let overlayBuffer = try TransparentVideoWriter.makePixelBuffer(from: overlayPool)
            let presentationTime = timing.presentationTime(for: frameIndex)
            let videoTime = CMTimeGetSeconds(presentationTime)

            ciContext.render(
                CIImage(cvPixelBuffer: sourceBuffer),
                to: outputBuffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )
            try renderer.render(videoTime: videoTime, into: overlayBuffer)
            let composed = CIImage(cvPixelBuffer: overlayBuffer).composited(over: CIImage(cvPixelBuffer: outputBuffer))
            ciContext.render(
                composed,
                to: outputBuffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )

            guard adaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
                throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec))
            }

            frameIndex += 1
            if frameIndex == timing.frameCount || frameIndex % Int(max(1, timing.framesPerSecond)) == 0 {
                config.progressHandler?(frameIndex, timing.frameCount)
            }
        }

        input.markAsFinished()
        if reader.status == .failed {
            writer.cancelWriting()
            throw OverlayVideoError.unreadableVideo(reader.error?.localizedDescription ?? "Source video reading failed.")
        }
        guard frameIndex > 0 else {
            writer.cancelWriting()
            throw OverlayVideoError.unreadableVideo("No video frames could be read from \(sourceVideoURL.path).")
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

    private func makeVideoComposition(track: AVAssetTrack, width: Int, height: Int) -> AVMutableVideoComposition {
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

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: config.duration, preferredTimescale: TransparentVideoFrameTiming.preferredTimescale)
        )
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = outputSize
        composition.frameDuration = CMTime(
            seconds: 1.0 / max(1, config.framesPerSecond),
            preferredTimescale: TransparentVideoFrameTiming.preferredTimescale
        )
        composition.renderScale = 1
        return composition
    }

    private func muxOriginalAudio(videoURL: URL, outputURL: URL) throws {
        let sourceAsset = AVURLAsset(url: sourceVideoURL)
        let videoAsset = AVURLAsset(url: videoURL)
        let audioTracks = sourceAsset.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            throw OverlayVideoError.writerFailed("Could not find rendered video track before audio muxing.")
        }

        let composition = AVMutableComposition()
        let duration = CMTime(seconds: config.duration, preferredTimescale: TransparentVideoFrameTiming.preferredTimescale)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

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
            let audioDuration = minTime(duration, audioTrack.timeRange.duration)
            guard audioDuration > .zero else { continue }
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: audioTrack,
                at: .zero
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
            throw OverlayVideoError.writerFailed(exportSession.error?.localizedDescription ?? "Audio muxing failed.")
        }
    }

    private func hasAudioTrack(in url: URL) -> Bool {
        !AVURLAsset(url: url).tracks(withMediaType: .audio).isEmpty
    }

    private func videoOutputSettings(
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
        if let encoderSpecification = TransparentVideoWriter.hardwareEncoderSpecification(
            codec: codec,
            hardwareProfile: hardwareProfile
        ) {
            settings[AVVideoEncoderSpecificationKey] = encoderSpecification
        }
        settings[AVVideoCompressionPropertiesKey] = [
            AVVideoAverageBitRateKey: averageBitRate,
            AVVideoExpectedSourceFrameRateKey: encoderFrameRate,
            AVVideoMaxKeyFrameIntervalKey: encoderFrameRate,
            AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_RealTime as String: true,
            kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true
        ]
        return settings
    }

    private func waitUntilReady(_ input: AVAssetWriterInput) throws {
        while !input.isReadyForMoreMediaData {
            if config.cancellationHandler?() == true {
                throw OverlayVideoError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
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
        guard let error else {
            return "Unknown writer failure while using \(codec.displayName)."
        }
        return "\(error.localizedDescription) while using \(codec.displayName)."
    }
}
