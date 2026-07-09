import Foundation

// MARK: - Timeline data model
//
// Foundation for the timeline editor (see the timeline plan). This models a project
// as a pool of media assets plus a stack of tracks holding clips. It is deliberately
// simple: sync is a clip's position on the timeline, trimming is a clip's edges/in-point.
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

    public init(
        outputWidth: Int,
        outputHeight: Int,
        framesPerSecond: Double,
        distanceUnit: OverlayDistanceUnit,
        assets: [MediaAsset] = [],
        tracks: [TimelineTrack] = []
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.framesPerSecond = framesPerSecond
        self.distanceUnit = distanceUnit
        self.assets = assets
        self.tracks = tracks
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
}

// MARK: - Migration from the single-source model

extension TimelineProject {
    /// Build a timeline that reproduces the current single-video + single-activity + sync-point
    /// model: one video track with one clip, and one overlay track with one overlay clip whose
    /// placement reproduces `sync` (`activity elapsed = video/timeline time + fitOffsetFromVideoStart`).
    ///
    /// The offset is folded into the clip's `timelineStart`/`sourceIn` so both stay non-negative:
    /// when the activity leads the video the overlay starts trimmed-in; when the video leads the
    /// activity the overlay clip starts later on the timeline. The clip's `duration` reflects the
    /// activity's real length (minus any trimmed-in head), so its timeline width is proportional to
    /// the activity — not stretched to match the video.
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

        let videoDuration = videoAsset?.duration ?? 0

        if let videoAsset {
            assets.append(videoAsset)
            let clip = TimelineClip(
                id: "single.video.clip",
                assetID: videoAsset.id,
                timelineStart: 0,
                duration: videoDuration,
                sourceIn: 0
            )
            tracks.append(TimelineTrack(id: "single.video.track", kind: .video, name: "V1", clips: [clip]))
        }

        if let activityAsset {
            assets.append(activityAsset)

            let start: TimeInterval
            let sourceIn: TimeInterval
            let duration: TimeInterval

            if videoAsset != nil {
                let offset = sync.fitOffsetFromVideoStart
                if offset >= 0 {
                    // Activity is ahead of the video: its first `offset` seconds run before the
                    // timeline origin, so the clip starts trimmed-in and shows the remaining length.
                    start = 0
                    sourceIn = offset
                    duration = max(0, activityAsset.duration - offset)
                } else {
                    // Video leads the activity: the overlay starts later and shows its full length,
                    // which may extend past the video when the activity outlasts it.
                    start = -offset
                    sourceIn = 0
                    duration = activityAsset.duration
                }
            } else {
                // Activity-only project: overlay spans its own duration from the timeline origin.
                start = 0
                sourceIn = 0
                duration = activityAsset.duration
            }

            let clip = TimelineClip(
                id: "single.overlay.clip",
                assetID: activityAsset.id,
                timelineStart: start,
                duration: duration,
                sourceIn: sourceIn,
                layout: layout,
                distanceUnit: distanceUnit
            )
            tracks.append(TimelineTrack(id: "single.overlay.track", kind: .overlay, name: "O1", clips: [clip]))
        }

        return TimelineProject(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            framesPerSecond: framesPerSecond,
            distanceUnit: distanceUnit,
            assets: assets,
            tracks: tracks
        )
    }
}
