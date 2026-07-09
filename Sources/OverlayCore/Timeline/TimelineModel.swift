import Foundation

// MARK: - Timeline data model
//
// Foundation for the timeline editor (see the timeline plan). This models a project
// as a pool of media assets plus a stack of tracks holding clips. It is deliberately
// simple: placement is a clip's relative position, source synchronization is an optional match
// point, and trimming is a clip's edges/in-point.
//
// Compositing order: `tracks` is bottom-to-top. Index 0 renders first (the base), and
// later tracks composite on top. This layer is pure data — rendering/export consume it
// elsewhere; it does not depend on any UI framework.

/// A single imported source: a video, or an activity file (FIT/GPX).
public struct MediaAsset: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case video
        case activity
    }

    public var id: String
    public var kind: Kind
    /// Location of the source on disk.
    public var url: URL
    /// Human-readable name shown in the media pool (usually the file name).
    public var displayName: String
    /// Source duration in seconds.
    public var duration: TimeInterval
    // Video-only metadata (nil for activity assets).
    public var width: Int?
    public var height: Int?
    public var framesPerSecond: Double?
    /// Optional security-scoped bookmark used by the sandboxed GUI app when reopening projects.
    public var bookmarkData: Data?

    public init(
        id: String,
        kind: Kind,
        url: URL,
        displayName: String,
        duration: TimeInterval,
        width: Int? = nil,
        height: Int? = nil,
        framesPerSecond: Double? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.displayName = displayName
        self.duration = duration
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.bookmarkData = bookmarkData
    }
}

/// Source-time correspondence used to align one video and one activity without coupling that
/// relationship to either clip's editable timeline position.
public struct TimelineSourceMatchPoint: Codable, Equatable {
    public var videoAssetID: String
    public var activityAssetID: String
    public var videoSourceTime: TimeInterval
    public var activitySourceTime: TimeInterval

    public init(
        videoAssetID: String,
        activityAssetID: String,
        videoSourceTime: TimeInterval,
        activitySourceTime: TimeInterval
    ) {
        self.videoAssetID = videoAssetID
        self.activityAssetID = activityAssetID
        self.videoSourceTime = videoSourceTime
        self.activitySourceTime = activitySourceTime
    }
}

/// A clip placed on a track: a span of an asset positioned on the timeline.
///
/// For a video track the clip renders source frames; for an overlay track it renders the
/// activity telemetry using `layout`. A timeline time `t` inside the clip maps to source
/// time `sourceIn + (t - timelineStart)` (activity elapsed for overlay clips).
public struct TimelineClip: Codable, Equatable, Identifiable {
    public var id: String
    /// References `MediaAsset.id`.
    public var assetID: String
    /// Position of the clip's left edge on the timeline, in seconds.
    public var timelineStart: TimeInterval
    /// Length of the clip on the timeline, in seconds.
    public var duration: TimeInterval
    /// Trim in-point within the source, in seconds.
    public var sourceIn: TimeInterval
    /// Per-clip overlay layout (overlay clips only; `nil` inherits the project layout).
    public var layout: OverlayLayout?
    /// Per-clip distance unit (overlay clips only; `nil` inherits the project setting).
    public var distanceUnit: OverlayDistanceUnit?

    public init(
        id: String,
        assetID: String,
        timelineStart: TimeInterval,
        duration: TimeInterval,
        sourceIn: TimeInterval = 0,
        layout: OverlayLayout? = nil,
        distanceUnit: OverlayDistanceUnit? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.timelineStart = timelineStart
        self.duration = duration
        self.sourceIn = sourceIn
        self.layout = layout
        self.distanceUnit = distanceUnit
    }

    /// Timeline time of the clip's right edge.
    public var timelineEnd: TimeInterval { timelineStart + duration }

    /// Whether a timeline time falls within this clip (inclusive start, exclusive end).
    public func contains(timelineTime t: TimeInterval) -> Bool {
        t >= timelineStart && t < timelineEnd
    }

    /// Source time (video time, or activity elapsed) for a timeline time.
    /// Not clamped to the source bounds — the compositor clamps as needed.
    public func sourceTime(atTimelineTime t: TimeInterval) -> TimeInterval {
        sourceIn + (t - timelineStart)
    }

    /// Timeline position at which a source time appears. This is the inverse of
    /// `sourceTime(atTimelineTime:)` and is useful when aligning source match points.
    public func timelineTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        timelineStart + (sourceTime - sourceIn)
    }
}

/// An ordered lane of clips of a single kind.
public struct TimelineTrack: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case video
        case overlay
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var isEnabled: Bool
    public var isLocked: Bool
    public var clips: [TimelineClip]

    public init(
        id: String,
        kind: Kind,
        name: String,
        isEnabled: Bool = true,
        isLocked: Bool = false,
        clips: [TimelineClip] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isEnabled = isEnabled
        self.isLocked = isLocked
        self.clips = clips
    }

    /// The clip covering a timeline time, if any. When clips overlap, the last one wins.
    public func clip(atTimelineTime t: TimeInterval) -> TimelineClip? {
        clips.last { $0.contains(timelineTime: t) }
    }
}

/// A whole project: output settings, imported assets, and a bottom-to-top stack of tracks.
public struct TimelineProject: Codable, Equatable {
    public var outputWidth: Int
    public var outputHeight: Int
    public var framesPerSecond: Double
    public var distanceUnit: OverlayDistanceUnit
    public var assets: [MediaAsset]
    /// Bottom-to-top compositing order (index 0 is the base).
    public var tracks: [TimelineTrack]
    /// Optional primary source match point. It is independent from mutable clip placement and is
    /// optional so timeline projects saved before this field existed remain decodable.
    public var sourceMatchPoint: TimelineSourceMatchPoint?

    public init(
        outputWidth: Int,
        outputHeight: Int,
        framesPerSecond: Double,
        distanceUnit: OverlayDistanceUnit,
        assets: [MediaAsset] = [],
        tracks: [TimelineTrack] = [],
        sourceMatchPoint: TimelineSourceMatchPoint? = nil
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.framesPerSecond = framesPerSecond
        self.distanceUnit = distanceUnit
        self.assets = assets
        self.tracks = tracks
        self.sourceMatchPoint = sourceMatchPoint
    }

    public func asset(id: String) -> MediaAsset? {
        assets.first { $0.id == id }
    }

    /// Overall timeline length: the furthest clip end across all tracks.
    public var duration: TimeInterval {
        tracks.flatMap(\.clips).map(\.timelineEnd).max() ?? 0
    }

    public func snappedTimelineTime(
        _ proposed: TimeInterval,
        threshold: TimeInterval,
        excludingClipID: String? = nil
    ) -> TimeInterval {
        let sanitized = max(0, proposed)
        guard sanitized.isFinite, threshold.isFinite, threshold > 0 else { return sanitized }

        var best = sanitized
        var bestDistance = threshold
        let candidates: [TimeInterval] = [0] + tracks
            .flatMap(\.clips)
            .filter { $0.id != excludingClipID }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }

        for candidate in candidates where candidate.isFinite && candidate >= 0 {
            let distance = abs(candidate - sanitized)
            if distance <= bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    /// Align one clip's source match point with another clip's source match point.
    ///
    /// The anchor keeps its timeline position whenever the moving clip can remain at or after
    /// timeline zero. If the relative placement would be negative, both clips shift right by the
    /// minimum amount required. Source in-points and durations are never changed.
    @discardableResult
    public mutating func alignMatchPoint(
        anchorClipID: String,
        anchorSourceTime: TimeInterval,
        movingClipID: String,
        movingSourceTime: TimeInterval
    ) -> Bool {
        guard anchorClipID != movingClipID,
              anchorSourceTime.isFinite,
              movingSourceTime.isFinite,
              let anchorLocation = clipLocation(id: anchorClipID),
              let movingLocation = clipLocation(id: movingClipID),
              !tracks[anchorLocation.track].isLocked,
              !tracks[movingLocation.track].isLocked else {
            return false
        }

        let anchor = tracks[anchorLocation.track].clips[anchorLocation.clip]
        let moving = tracks[movingLocation.track].clips[movingLocation.clip]
        let anchorMatchTime = anchor.timelineTime(forSourceTime: anchorSourceTime)
        let proposedMovingStart = anchorMatchTime - (movingSourceTime - moving.sourceIn)
        guard proposedMovingStart.isFinite else { return false }

        let originShift = max(0, -proposedMovingStart)
        let anchorStart = max(0, anchor.timelineStart + originShift)
        let movingStart = max(0, proposedMovingStart + originShift)
        guard abs(anchor.timelineStart - anchorStart) > 1e-9
                || abs(moving.timelineStart - movingStart) > 1e-9 else {
            return false
        }

        tracks[anchorLocation.track].clips[anchorLocation.clip].timelineStart = anchorStart
        tracks[movingLocation.track].clips[movingLocation.clip].timelineStart = movingStart
        return true
    }

    private func clipLocation(id: String) -> (track: Int, clip: Int)? {
        for trackIndex in tracks.indices {
            if let clipIndex = tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                return (trackIndex, clipIndex)
            }
        }
        return nil
    }
}

// MARK: - Migration from the single-source model

extension TimelineProject {
    /// Build a timeline that reproduces the current single-video + single-activity + sync-point
    /// model: one video track with one clip, and one overlay track with one overlay clip whose
    /// placement reproduces `sync` by aligning the two source match points on the timeline.
    /// Both sources remain complete (`sourceIn == 0`); if either relative start would be negative,
    /// the pair shifts right together instead of trimming away source content.
    ///
    /// Track/clip IDs are deterministic (not random), so re-deriving this project each render yields
    /// stable identities — SwiftUI keeps a clip's view (and its in-flight drag gesture) alive across
    /// the many recomputations a sync drag triggers.
    public static func migratingSingleSource(
        outputWidth: Int,
        outputHeight: Int,
        framesPerSecond: Double,
        distanceUnit: OverlayDistanceUnit,
        videoAsset: MediaAsset?,
        activityAsset: MediaAsset?,
        sync: TelemetryTimeSync,
        layout: OverlayLayout
    ) -> TimelineProject {
        var assets: [MediaAsset] = []
        var tracks: [TimelineTrack] = []

        if let videoAsset {
            assets.append(videoAsset)
            let clip = TimelineClip(
                id: "single.video.clip",
                assetID: videoAsset.id,
                timelineStart: 0,
                duration: videoAsset.duration,
                sourceIn: 0
            )
            tracks.append(TimelineTrack(id: "single.video.track", kind: .video, name: "V1", clips: [clip]))
        }

        if let activityAsset {
            assets.append(activityAsset)
            let clip = TimelineClip(
                id: "single.overlay.clip",
                assetID: activityAsset.id,
                timelineStart: 0,
                duration: activityAsset.duration,
                sourceIn: 0,
                layout: layout,
                distanceUnit: distanceUnit
            )
            tracks.append(TimelineTrack(id: "single.overlay.track", kind: .overlay, name: "O1", clips: [clip]))
        }

        var project = TimelineProject(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            framesPerSecond: framesPerSecond,
            distanceUnit: distanceUnit,
            assets: assets,
            tracks: tracks,
            sourceMatchPoint: videoAsset.flatMap { video in
                activityAsset.map { activity in
                    TimelineSourceMatchPoint(
                        videoAssetID: video.id,
                        activityAssetID: activity.id,
                        videoSourceTime: sync.videoSyncTime,
                        activitySourceTime: sync.fitSyncTime
                    )
                }
            }
        )
        if videoAsset != nil, activityAsset != nil {
            project.alignMatchPoint(
                anchorClipID: "single.video.clip",
                anchorSourceTime: sync.videoSyncTime,
                movingClipID: "single.overlay.clip",
                movingSourceTime: sync.fitSyncTime
            )
        }
        return project
    }
}
