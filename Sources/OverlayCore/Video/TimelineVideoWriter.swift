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
        switch config.codec.exportMode {
        case .video:
            try writeCompositedVideo()
        case .overlay:
            try writeTransparentOverlay()
        }
    }

    private func writeCompositedVideo() throws {
        let singleSource = try makeSingleSourceComposition()
        let timelineToVideoOffset = singleSource.videoClip.sourceIn - singleSource.videoClip.timelineStart
        let timelineToActivityOffset = singleSource.overlayClip.sourceIn - singleSource.overlayClip.timelineStart
        let activityOffsetFromVideo = timelineToActivityOffset - timelineToVideoOffset
        let videoStartTime = singleSource.videoClip.sourceTime(atTimelineTime: config.timelineStart)

        guard videoStartTime.isFinite, videoStartTime >= 0 else {
            throw OverlayVideoError.invalidConfiguration("Timeline export maps to an invalid source video start time.")
        }

        try CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: singleSource.videoAsset.url,
            series: singleSource.series,
            config: CompositedVideoWriterConfig(
                width: config.width,
                height: config.height,
                framesPerSecond: config.framesPerSecond,
                startTime: videoStartTime,
                duration: config.duration,
                averageBitRate: config.averageBitRate,
                timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: activityOffsetFromVideo),
                codec: config.codec,
                overlayLayout: singleSource.overlayClip.layout ?? .default,
                distanceUnit: singleSource.overlayClip.distanceUnit ?? project.distanceUnit,
                activityTrim: config.activityTrim,
                progressHandler: config.progressHandler,
                cancellationHandler: config.cancellationHandler,
                diagnosticsHandler: config.diagnosticsHandler
            )
        ).write()
    }

    private func writeTransparentOverlay() throws {
        let overlay = try makeSingleOverlayComposition()
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

    private func makeSingleSourceComposition() throws -> (
        videoAsset: MediaAsset,
        videoClip: TimelineClip,
        overlayClip: TimelineClip,
        series: TelemetrySeries
    ) {
        let videoClips = enabledClips(kind: .video)
        let overlayClips = enabledClips(kind: .overlay)

        guard videoClips.count == 1, let videoClip = videoClips.first else {
            throw OverlayVideoError.invalidConfiguration("Timeline video export currently requires exactly one enabled video clip.")
        }
        guard overlayClips.count == 1, let overlayClip = overlayClips.first else {
            throw OverlayVideoError.invalidConfiguration("Timeline video export currently requires exactly one enabled overlay clip.")
        }
        guard let videoAsset = project.asset(id: videoClip.assetID), videoAsset.kind == .video else {
            throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
        }
        guard let overlayAsset = project.asset(id: overlayClip.assetID), overlayAsset.kind == .activity else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay clip references a missing activity asset.")
        }
        guard let series = telemetrySeriesByAssetID[overlayAsset.id] else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay clip has no loaded telemetry series.")
        }

        let timelineEnd = config.timelineStart + config.duration
        guard config.timelineStart >= videoClip.timelineStart,
              timelineEnd <= videoClip.timelineEnd + 1e-6 else {
            throw OverlayVideoError.invalidConfiguration("Timeline video export range must be covered by the enabled video clip.")
        }

        return (videoAsset, videoClip, overlayClip, series)
    }

    private func makeSingleOverlayComposition() throws -> (
        clip: TimelineClip,
        series: TelemetrySeries
    ) {
        let overlayClips = enabledClips(kind: .overlay)
        guard overlayClips.count == 1, let overlayClip = overlayClips.first else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay export currently requires exactly one enabled overlay clip.")
        }
        guard let overlayAsset = project.asset(id: overlayClip.assetID), overlayAsset.kind == .activity else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay clip references a missing activity asset.")
        }
        guard let series = telemetrySeriesByAssetID[overlayAsset.id] else {
            throw OverlayVideoError.invalidConfiguration("Timeline overlay clip has no loaded telemetry series.")
        }
        return (overlayClip, series)
    }

    private func enabledClips(kind: TimelineTrack.Kind) -> [TimelineClip] {
        project.tracks
            .filter { $0.kind == kind && $0.isEnabled }
            .flatMap(\.clips)
    }
}
