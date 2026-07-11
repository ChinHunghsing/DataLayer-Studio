import Foundation

/// Places newly imported assets on the timeline by real-world recording time.
///
/// Video files carry a container creation date and FIT/GPX activities carry absolute
/// timestamps (both surfaced as `MediaAsset.wallClockStart`). When an already placed clip's
/// asset has a known recording start, the two sources share one real-world clock, so a new
/// asset's correct relative position can be computed instead of appending it at a lane's end.
/// A placement is an insertion hint only — existing clips are never repositioned.
public enum TimelineAutoAlignment {
    /// Footage belonging to one project is recorded within hours of the rest. A computed
    /// position further than this beyond the existing content very likely belongs to a
    /// different session, so it is rejected instead of silently stretching the timeline.
    public static let maximumReasonableGap: TimeInterval = 24 * 60 * 60

    /// Device clocks disagree by fractions of a second; treat a slightly negative candidate
    /// as "starts together with the timeline" instead of rejecting it.
    private static let negativeTolerance: TimeInterval = 1

    public enum Placement: Equatable {
        /// Insert the new asset at this timeline time.
        case aligned(TimeInterval)
        /// No placed clip has a known recording start to align against.
        case noReference
        /// The new asset carries no recording time.
        case missingWallClock
        /// A position was computed but lies before timeline zero or implausibly far away.
        case unreasonable
    }

    /// Timeline position for a new asset, derived from the earliest placed clip whose asset
    /// has a known recording start.
    public static func placement(
        forAssetWallClockStart start: Date?,
        in project: TimelineProject
    ) -> Placement {
        guard let reference = referenceClip(in: project) else { return .noReference }
        guard let start else { return .missingWallClock }
        // Wall clock at timeline zero: the reference clip's left edge shows source time
        // `sourceIn`, which was recorded at `wallClockStart + sourceIn`.
        let timelineZero = reference.wallClockStart
            .addingTimeInterval(reference.clip.sourceIn - reference.clip.timelineStart)
        let candidate = start.timeIntervalSince(timelineZero)
        guard candidate >= -negativeTolerance,
              candidate <= project.duration + maximumReasonableGap else {
            return .unreasonable
        }
        return .aligned(max(0, candidate))
    }

    public enum SingleSourceAlignment: Equatable {
        case aligned(videoSourceTime: TimeInterval, activitySourceTime: TimeInterval)
        /// The video or the activity carries no recording time.
        case missingWallClock
        /// Recording times exist but are too far apart to belong to one session.
        case gapTooLarge
    }

    /// Source match point for the single-video + single-activity model: at the returned
    /// video source time the activity is at the returned activity source time. One of the
    /// two is always zero — the source that started later begins at its own start.
    public static func singleSourceAlignment(
        videoWallClockStart: Date?,
        activityWallClockStart: Date?
    ) -> SingleSourceAlignment {
        guard let videoWallClockStart, let activityWallClockStart else { return .missingWallClock }
        let delta = activityWallClockStart.timeIntervalSince(videoWallClockStart)
        guard abs(delta) <= maximumReasonableGap else { return .gapTooLarge }
        return .aligned(videoSourceTime: max(0, delta), activitySourceTime: max(0, -delta))
    }

    private static func referenceClip(
        in project: TimelineProject
    ) -> (clip: TimelineClip, wallClockStart: Date)? {
        var earliest: (clip: TimelineClip, wallClockStart: Date)?
        for track in project.tracks {
            for clip in track.clips {
                guard let wallClockStart = project.asset(id: clip.assetID)?.wallClockStart else { continue }
                if let current = earliest, current.clip.timelineStart <= clip.timelineStart { continue }
                earliest = (clip, wallClockStart)
            }
        }
        return earliest
    }
}
