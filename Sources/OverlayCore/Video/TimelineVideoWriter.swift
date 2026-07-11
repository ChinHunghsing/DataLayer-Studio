import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation

public struct TimelineVideoWriterConfig {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var timelineStart: TimeInterval
    public var duration: TimeInterval
    public var averageBitRate: Int
    public var codec: OverlayVideoCodec
    public var activityTrim: ActivityTrim
    public var progressHandler: ((Int, Int) -> Void)?
    public var cancellationHandler: (() -> Bool)?
    public var diagnosticsHandler: ((String) -> Void)?

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Double,
        timelineStart: TimeInterval = 0,
        duration: TimeInterval,
        averageBitRate: Int = 12_000_000,
        codec: OverlayVideoCodec = .hevc,
        activityTrim: ActivityTrim = .none,
        progressHandler: ((Int, Int) -> Void)? = nil,
        cancellationHandler: (() -> Bool)? = nil,
        diagnosticsHandler: ((String) -> Void)? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.timelineStart = timelineStart
        self.duration = duration
        self.averageBitRate = averageBitRate
        self.codec = codec
        self.activityTrim = activityTrim
        self.progressHandler = progressHandler
        self.cancellationHandler = cancellationHandler
        self.diagnosticsHandler = diagnosticsHandler
    }
}

public final class TimelineVideoWriter {
    private let outputURL: URL
    private let project: TimelineProject
    private let telemetrySeriesByAssetID: [String: TelemetrySeries]
    private let config: TimelineVideoWriterConfig

    public init(
        outputURL: URL,
        project: TimelineProject,
        telemetrySeriesByAssetID: [String: TelemetrySeries],
        config: TimelineVideoWriterConfig
    ) {
        self.outputURL = outputURL
        self.project = project
        self.telemetrySeriesByAssetID = telemetrySeriesByAssetID
        self.config = config
    }

    public func write() throws {
        if let issue = project.firstExportValidationIssue(
            mode: config.codec.exportMode,
            timelineStart: config.timelineStart,
            duration: config.duration,
            availableTelemetryAssetIDs: Set(telemetrySeriesByAssetID.keys)
        ) {
            throw OverlayVideoError.invalidConfiguration(issue.errorDescription)
        }

        switch config.codec.exportMode {
        case .video:
            try writeCompositedVideo()
        case .overlay:
            try writeTransparentOverlay()
        }
    }

    private func writeCompositedVideo() throws {
        let videoClips = try project.validatedVideoClipsForExport(
            timelineStart: config.timelineStart,
            duration: config.duration
        )
        let video = try videoClips.isEmpty ? nil : makeCompositedVideoSource(videoClips)
        let overlays = try makeOverlayCompositions()
        let overlaysByClipID = overlayCompositionsByClipID(overlays)

        let renderPool = try TransparentVideoWriter.makePixelBufferPool(
            width: config.width,
            height: config.height,
            minimumBufferCount: overlays.count + 2
        )
        let hardwareProfile = OverlayHardwareProfile.current
        let compositeContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(x: 0, y: 0, width: config.width, height: config.height)

        let writerConfig = CompositedVideoWriterConfig(
            width: config.width,
            height: config.height,
            framesPerSecond: config.framesPerSecond,
            startTime: video?.startTime ?? 0,
            duration: config.duration,
            averageBitRate: config.averageBitRate,
            codec: config.codec,
            activityTrim: config.activityTrim,
            progressHandler: config.progressHandler,
            cancellationHandler: config.cancellationHandler,
            diagnosticsHandler: config.diagnosticsHandler
        )
        let renderOverlay: (TimeInterval, CVPixelBuffer) throws -> Void = { timelineTime, overlayBuffer in
            let activeOverlays = self.activeOverlayCompositions(
                atTimelineTime: timelineTime,
                compositionsByClipID: overlaysByClipID
            )
            let renderedBuffer = try self.renderTransparentFrame(
                activeOverlays,
                timelineTime: timelineTime,
                renderPool: renderPool,
                compositeContext: compositeContext,
                colorSpace: colorSpace
            )
            compositeContext.render(
                CIImage(cvPixelBuffer: renderedBuffer),
                to: overlayBuffer,
                bounds: bounds,
                colorSpace: colorSpace
            )
        }

        let writer: CompositedVideoWriter
        if let video {
            writer = CompositedVideoWriter(
                outputURL: outputURL,
                sourceAsset: video.asset,
                sourceDescription: video.description,
                sourceVideoRanges: video.videoRanges,
                sourceVideoComposition: video.videoComposition,
                config: writerConfig,
                overlayStartTime: config.timelineStart,
                renderOverlay: renderOverlay
            )
        } else {
            writer = CompositedVideoWriter(
                outputURL: outputURL,
                config: writerConfig,
                overlayStartTime: config.timelineStart,
                renderOverlay: renderOverlay
            )
        }
        try writer.write()
    }

    private func writeTransparentOverlay() throws {
        let overlays = try makeOverlayCompositions()
        if overlays.count != 1 || !clipCoversExportRange(overlays[0].clip) {
            try writeMultiTransparentOverlay(overlays)
            return
        }

        let overlay = overlays[0]
        let activityOffsetFromTimeline = overlay.clip.sourceIn - overlay.clip.timelineStart

        try TransparentVideoWriter(
            outputURL: outputURL,
            series: overlay.series,
            config: TransparentVideoWriterConfig(
                width: config.width,
                height: config.height,
                framesPerSecond: config.framesPerSecond,
                startTime: config.timelineStart,
                duration: config.duration,
                averageBitRate: config.averageBitRate,
                timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: activityOffsetFromTimeline),
                codec: config.codec,
                overlayLayout: overlay.clip.layout ?? .default,
                distanceUnit: overlay.clip.distanceUnit ?? project.distanceUnit,
                activityTrim: config.activityTrim,
                progressHandler: config.progressHandler,
                cancellationHandler: config.cancellationHandler
            )
        ).write()
    }

    private func writeMultiTransparentOverlay(_ overlays: [OverlayComposition]) throws {
        try validateTransparentConfiguration()
        let overlaysByClipID = overlayCompositionsByClipID(overlays)

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
        let frameCount = timing.frameCount
        let fps = timing.framesPerSecond
        let encoderFrameRate = try encoderFrameRateValue(fps)
        let hardwareProfile = OverlayHardwareProfile.current
        TransparentVideoWriter.removeStaleTemporaryOutputs()
        let temporaryOutputURL = makeTemporaryOutputURL(tag: "timeline-overlay")
        removePartialOutput(at: temporaryOutputURL)

        do {
            let writer = try AVAssetWriter(outputURL: temporaryOutputURL, fileType: .mov)
            writer.movieTimeScale = timing.mediaTimeScale
            let settings = TransparentVideoWriter.videoOutputSettings(
                width: width,
                height: height,
                codec: config.codec,
                averageBitRate: config.averageBitRate,
                encoderFrameRate: encoderFrameRate,
                expectedSourceFrameRate: fps,
                hardwareProfile: hardwareProfile
            )
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
            guard writer.startWriting() else {
                throw OverlayVideoError.cannotStartWriter(describe(error: writer.error, codec: config.codec))
            }
            writer.startSession(atSourceTime: .zero)

            let renderQueue = DispatchQueue(label: "run.libo.overlay.timeline-video-writer")
            let renderFinished = DispatchSemaphore(value: 0)
            let renderPool = try TransparentVideoWriter.makePixelBufferPool(
                width: width,
                height: height,
                minimumBufferCount: overlays.count + 2
            )
            let alphaContext = config.codec == .hevcAlpha
                ? OverlayCIContextFactory.makeContext(profile: hardwareProfile)
                : nil
            let compositeContext = OverlayCIContextFactory.makeContext(profile: hardwareProfile)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var frameIndex = 0
            var renderError: Error?
            var didFinishInput = false

            input.requestMediaDataWhenReady(on: renderQueue) {
                while input.isReadyForMoreMediaData, frameIndex < frameCount, renderError == nil {
                    do {
                        try autoreleasepool {
                            if self.config.cancellationHandler?() == true {
                                throw OverlayVideoError.cancelled
                            }

                            guard let appendPool = adaptor.pixelBufferPool else {
                                throw OverlayVideoError.cannotCreatePixelBuffer
                            }
                            let presentationTime = timing.presentationTime(for: frameIndex)
                            let timelineTime = self.config.timelineStart + CMTimeGetSeconds(presentationTime)
                            let activeOverlays = self.activeOverlayCompositions(
                                atTimelineTime: timelineTime,
                                compositionsByClipID: overlaysByClipID
                            )
                            let renderedBuffer = try self.renderTransparentFrame(
                                activeOverlays,
                                timelineTime: timelineTime,
                                renderPool: renderPool,
                                compositeContext: compositeContext,
                                colorSpace: colorSpace
                            )

                            let appendBuffer: CVPixelBuffer
                            if let alphaContext {
                                appendBuffer = try TransparentVideoWriter.makePixelBuffer(from: appendPool)
                                TransparentVideoWriter.prepareHEVCAlphaForEncoding(
                                    from: renderedBuffer,
                                    to: appendBuffer,
                                    context: alphaContext,
                                    colorSpace: colorSpace
                                )
                            } else {
                                appendBuffer = renderedBuffer
                                TransparentVideoWriter.preparePremultipliedAlphaForEncoding(on: appendBuffer)
                            }

                            guard try TransparentVideoWriter.appendPixelBuffer(
                                appendBuffer,
                                to: input,
                                at: presentationTime,
                                duration: timing.frameDuration
                            ) else {
                                throw OverlayVideoError.writerFailed(self.describe(error: writer.error, codec: self.config.codec))
                            }

                            frameIndex += 1
                            if frameIndex == frameCount || frameIndex % Int(max(1, fps)) == 0 {
                                self.config.progressHandler?(frameIndex, frameCount)
                            }
                        }
                    } catch {
                        renderError = error
                    }
                }

                if (frameIndex >= frameCount || renderError != nil), !didFinishInput {
                    didFinishInput = true
                    writer.endSession(atSourceTime: timing.outputDuration)
                    input.markAsFinished()
                    renderFinished.signal()
                }
            }
            renderFinished.wait()

            if let renderError {
                writer.cancelWriting()
                throw renderError
            }

            let finishSemaphore = DispatchSemaphore(value: 0)
            writer.finishWriting { finishSemaphore.signal() }
            finishSemaphore.wait()

            guard writer.status == .completed else {
                throw OverlayVideoError.writerFailed(describe(error: writer.error, codec: config.codec))
            }
            try installCompletedOutput(from: temporaryOutputURL)
        } catch {
            removePartialOutput(at: temporaryOutputURL)
            throw error
        }
    }

    private func renderTransparentFrame(
        _ overlays: [OverlayComposition],
        timelineTime: TimeInterval,
        renderPool: CVPixelBufferPool,
        compositeContext: CIContext,
        colorSpace: CGColorSpace
    ) throws -> CVPixelBuffer {
        var accumulated = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
        clearPixelBuffer(accumulated)

        for overlay in overlays {
            let layerBuffer = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
            try overlay.renderer.render(videoTime: timelineTime, into: layerBuffer)

            let composed = try TransparentVideoWriter.makePixelBuffer(from: renderPool)
            clearPixelBuffer(composed)
            let image = CIImage(cvPixelBuffer: layerBuffer)
                .composited(over: CIImage(cvPixelBuffer: accumulated))
            compositeContext.render(
                image,
                to: composed,
                bounds: CGRect(x: 0, y: 0, width: config.width, height: config.height),
                colorSpace: colorSpace
            )
            accumulated = composed
        }

        return accumulated
    }

    private func overlayCompositionsByClipID(
        _ overlays: [OverlayComposition]
    ) -> [String: OverlayComposition] {
        overlays.reduce(into: [:]) { result, composition in
            result[composition.clip.id] = composition
        }
    }

    private func activeOverlayCompositions(
        atTimelineTime timelineTime: TimeInterval,
        compositionsByClipID: [String: OverlayComposition]
    ) -> [OverlayComposition] {
        project.activeClips(kind: .overlay, atTimelineTime: timelineTime).compactMap {
            compositionsByClipID[$0.id]
        }
    }

    private func clipCoversExportRange(_ clip: TimelineClip) -> Bool {
        let epsilon = 1e-6
        return clip.timelineStart <= config.timelineStart + epsilon
            && clip.timelineEnd >= config.timelineStart + config.duration - epsilon
    }

    private func makeCompositedVideoSource(
        _ videoClips: [TimelineClip]
    ) throws -> (
        asset: AVAsset,
        description: String,
        startTime: TimeInterval,
        videoRanges: [CMTimeRange]?,
        videoComposition: AVVideoComposition?
    ) {
        if videoClips.count == 1, clipCoversExportRange(videoClips[0]) {
            let clip = videoClips[0]
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let startTime = clip.sourceTime(atTimelineTime: config.timelineStart)
            guard startTime.isFinite, startTime >= 0 else {
                throw OverlayVideoError.invalidConfiguration("Timeline export maps to an invalid source video start time.")
            }
            return (AVURLAsset(url: videoAsset.url), videoAsset.url.path, startTime, nil, nil)
        }

        let timelineComposition = try makeTimelineVideoComposition(videoClips)
        return (
            timelineComposition.asset,
            "sparse timeline video composition",
            config.timelineStart,
            timelineComposition.videoRanges,
            timelineComposition.videoComposition
        )
    }

    private func makeTimelineVideoComposition(
        _ videoClips: [TimelineClip]
    ) throws -> (
        asset: AVAsset,
        videoRanges: [CMTimeRange],
        videoComposition: AVVideoComposition
    ) {
        let built = try TimelineVideoCompositionBuilder.make(
            project: project,
            videoClips: videoClips,
            requiredEnd: config.timelineStart + config.duration,
            renderSize: CGSize(width: config.width, height: config.height),
            framesPerSecond: config.framesPerSecond
        )
        return (built.composition, built.videoRanges, built.videoComposition)
    }

    private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private func makeOverlayCompositions() throws -> [OverlayComposition] {
        let overlayClips = project.enabledClips(kind: .overlay)
        guard !overlayClips.isEmpty else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay export requires at least one enabled overlay clip.")
        }

        return try overlayClips.map { clip in
            guard let overlayAsset = project.asset(id: clip.assetID), overlayAsset.kind == .activity else {
                throw OverlayVideoError.invalidConfiguration("Timeline overlay clip references a missing activity asset.")
            }
            guard let series = telemetrySeriesByAssetID[overlayAsset.id] else {
                throw OverlayVideoError.invalidConfiguration("Timeline overlay clip has no loaded telemetry series.")
            }
            let renderer = OverlayRenderer(
                series: series,
                config: OverlayRenderConfig(
                    size: CGSize(width: config.width, height: config.height),
                    timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: clip.sourceIn - clip.timelineStart),
                    layout: clip.layout ?? .default,
                    distanceUnit: clip.distanceUnit ?? project.distanceUnit,
                    activityTrim: config.activityTrim
                )
            )
            return OverlayComposition(clip: clip, series: series, renderer: renderer)
        }
    }

    private func validateTransparentConfiguration() throws {
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
        guard config.timelineStart.isFinite, config.timelineStart >= 0 else {
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
        guard config.codec.exportMode == .overlay else {
            throw OverlayVideoError.invalidConfiguration("\(config.codec.displayName) cannot be used for transparent overlay export.")
        }
        try validateOutputURL()
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

    private func makeTemporaryOutputURL(tag: String) -> URL {
        TransparentVideoWriter.makeTemporaryOutputURL(
            for: outputURL,
            tag: tag,
            fallbackBaseName: tag
        )
    }

    private func installCompletedOutput(from temporaryOutputURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                if !isMissingFileError(error) {
                    throw OverlayVideoError.writerFailed(
                        "Could not replace existing output file: \(error.localizedDescription)"
                    )
                }
            }
        }

        do {
            do {
                try fileManager.moveItem(at: temporaryOutputURL, to: outputURL)
            } catch {
                try fileManager.copyItem(at: temporaryOutputURL, to: outputURL)
                try? fileManager.removeItem(at: temporaryOutputURL)
            }
        } catch {
            throw OverlayVideoError.writerFailed(
                "Could not move completed output into place: \(error.localizedDescription)"
            )
        }
    }

    private func removePartialOutput(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func clearPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        memset(baseAddress, 0, bytesPerRow * height)
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == ENOENT {
            return true
        }
        return false
    }

    private func describe(error: Error?, codec: OverlayVideoCodec) -> String {
        guard let error else {
            return "AVAssetWriter failed while using \(codec.displayName)."
        }
        return "\(codec.displayName): \(error.localizedDescription)"
    }

    private struct OverlayComposition {
        var clip: TimelineClip
        var series: TelemetrySeries
        var renderer: OverlayRenderer
    }
}
