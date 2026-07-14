import Foundation

// MARK: - Timeline clip editing (split / delete / ripple delete)
//
// Simplified DaVinci-style editing semantics for the timeline tab:
// - Splitting cuts every unlocked clip under a timeline time, or only an explicitly selected clip,
//   into two clips whose source content stays continuous across the cut.
// - Removing a clip leaves a gap; gaps are legal timeline content (composited export
//   fills them with black frames, overlay-only export keeps them transparent).
// - Ripple-removing a clip also closes its time range on every unlocked track so
//   video and overlay stay in sync; clips spanning the range are trimmed or split.

extension TimelineTrack {
    /// Occupied spans of every clip except `excludingClipID`, merged and sorted. Legacy projects
    /// may still contain overlapping clips; merging keeps the gap math well-defined for them.
    private func occupiedIntervals(excludingClipID: String?) -> [(start: TimeInterval, end: TimeInterval)] {
        let spans = clips
            .filter { $0.id != excludingClipID && $0.duration > 0 }
            .map { (start: $0.timelineStart, end: $0.timelineEnd) }
            .sorted { $0.start < $1.start }
        var merged: [(start: TimeInterval, end: TimeInterval)] = []
        for span in spans {
            if var last = merged.last, span.start <= last.end {
                last.end = max(last.end, span.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// The start closest to `proposedStart` where a clip of `duration` fits on this track without
    /// overlapping any other clip. Clips may touch (intervals are half-open); the gap after the
    /// last clip is unbounded, so a fitting position always exists.
    public func nonOverlappingStart(
        forClipID clipID: String,
        duration: TimeInterval,
        proposedStart: TimeInterval
    ) -> TimeInterval {
        let sanitized = max(0, proposedStart.isFinite ? proposedStart : 0)
        guard duration.isFinite, duration > 0 else { return sanitized }

        let intervals = occupiedIntervals(excludingClipID: clipID)
        var best: TimeInterval?
        var bestDistance = TimeInterval.infinity
        var gapStart: TimeInterval = 0
        for interval in intervals + [(start: TimeInterval.infinity, end: TimeInterval.infinity)] {
            let gapEnd = interval.start
            if gapEnd - gapStart >= duration - 1e-9 {
                let clamped = min(max(sanitized, gapStart), gapEnd - duration)
                let distance = abs(clamped - sanitized)
                if distance < bestDistance {
                    best = clamped
                    bestDistance = distance
                }
            }
            gapStart = max(gapStart, interval.end)
        }
        return max(0, best ?? gapStart)
    }

    /// First non-overlapping position at or after `proposedStart`. Used for provisional imports so
    /// a failed automatic alignment never makes a newly added clip jump earlier than its anchor.
    public func nonOverlappingStartAtOrAfter(
        forClipID clipID: String,
        duration: TimeInterval,
        proposedStart: TimeInterval
    ) -> TimeInterval {
        var candidate = max(0, proposedStart.isFinite ? proposedStart : 0)
        guard duration.isFinite, duration > 0 else { return candidate }
        for interval in occupiedIntervals(excludingClipID: clipID) {
            guard candidate < interval.end, candidate + duration > interval.start else { continue }
            candidate = interval.end
        }
        return candidate
    }

    /// Free space around an existing clip: the nearest other-clip end at or before the clip's
    /// start, and the nearest other-clip start at or after the clip's end (`nil` when unbounded).
    /// Trims must stay inside these bounds to keep the track overlap-free.
    public func neighborBounds(aroundClipID clipID: String) -> (lower: TimeInterval, upper: TimeInterval?) {
        guard let clip = clips.first(where: { $0.id == clipID }) else { return (0, nil) }
        let tolerance: TimeInterval = 1e-9
        let intervals = occupiedIntervals(excludingClipID: clipID)
        let lower = intervals
            .map(\.end)
            .filter { $0 <= clip.timelineStart + tolerance }
            .max() ?? 0
        let upper = intervals
            .map(\.start)
            .filter { $0 >= clip.timelineEnd - tolerance }
            .min()
        return (max(0, lower), upper)
    }

    /// Longest duration a clip starting at `start` can have before hitting the next clip
    /// (`nil` when nothing follows).
    public func maximumNonOverlappingDuration(
        forClipID clipID: String,
        startingAt start: TimeInterval
    ) -> TimeInterval? {
        let next = occupiedIntervals(excludingClipID: clipID)
            .map(\.start)
            .filter { $0 >= start - 1e-9 }
            .min()
        return next.map { max(0, $0 - start) }
    }
}

extension TimelineProject {
    /// Minimum piece length produced by a split, matching the interactive trim floor.
    public static let minimumEditableClipDuration: TimeInterval = 0.1

    /// IDs of clips that `splitClips(atTimelineTime:clipID:)` would cut. With no `clipID`, every
    /// unlocked clip under the playhead is targeted; otherwise only that selected clip is considered.
    public func splittableClipIDs(
        atTimelineTime t: TimeInterval,
        clipID: String? = nil
    ) -> [String] {
        guard t.isFinite else { return [] }
        return tracks
            .filter { !$0.isLocked }
            .flatMap(\.clips)
            .filter {
                (clipID == nil || $0.id == clipID)
                    && t - $0.timelineStart >= Self.minimumEditableClipDuration
                    && $0.timelineEnd - t >= Self.minimumEditableClipDuration
            }
            .map(\.id)
    }

    /// Cut every splittable clip at `t` into two clips. The left piece keeps the clip's identity
    /// (selection survives); the right piece continues the same source content under a new ID.
    /// Returns the number of clips that were split.
    @discardableResult
    public mutating func splitClips(
        atTimelineTime t: TimeInterval,
        clipID: String? = nil,
        makeClipID: () -> String = { UUID().uuidString }
    ) -> Int {
        let targets = Set(splittableClipIDs(atTimelineTime: t, clipID: clipID))
        guard !targets.isEmpty else { return 0 }

        var splitCount = 0
        for trackIndex in tracks.indices where !tracks[trackIndex].isLocked {
            var clips: [TimelineClip] = []
            clips.reserveCapacity(tracks[trackIndex].clips.count + targets.count)
            for clip in tracks[trackIndex].clips {
                guard targets.contains(clip.id) else {
                    clips.append(clip)
                    continue
                }
                var left = clip
                left.duration = t - clip.timelineStart
                var right = clip
                right.id = makeClipID()
                right.timelineStart = t
                right.sourceIn = clip.sourceIn + (t - clip.timelineStart)
                right.duration = clip.timelineEnd - t
                clips.append(left)
                clips.append(right)
                splitCount += 1
            }
            tracks[trackIndex].clips = clips
        }
        return splitCount
    }

    /// Remove one clip from an unlocked track, leaving a gap.
    @discardableResult
    public mutating func removeClip(id: String) -> Bool {
        for trackIndex in tracks.indices where !tracks[trackIndex].isLocked {
            if let clipIndex = tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                tracks[trackIndex].clips.remove(at: clipIndex)
                return true
            }
        }
        return false
    }

    /// Remove one clip and close its time range on every unlocked track (ripple delete).
    @discardableResult
    public mutating func rippleRemoveClip(
        id: String,
        makeClipID: () -> String = { UUID().uuidString }
    ) -> Bool {
        let clip = tracks
            .filter { !$0.isLocked }
            .flatMap(\.clips)
            .first { $0.id == id }
        guard let clip, removeClip(id: id) else { return false }
        removeTimeRange(from: clip.timelineStart, to: clip.timelineEnd, makeClipID: makeClipID)
        return true
    }

    /// Close `[start, end)` on every unlocked track: later clips shift left, clips spanning the
    /// range are trimmed (or split into head and tail) so their surviving source content keeps
    /// its position relative to the shortened timeline. Locked tracks keep their clips in place.
    ///
    /// The mapping `t -> t - (end - start)` for `t >= end` and identity for `t <= start` is
    /// monotone, so a track with no overlapping clips cannot gain overlaps.
    public mutating func removeTimeRange(
        from start: TimeInterval,
        to end: TimeInterval,
        makeClipID: () -> String = { UUID().uuidString }
    ) {
        guard start.isFinite, end.isFinite, end > start, start >= 0 else { return }
        let width = end - start

        for trackIndex in tracks.indices where !tracks[trackIndex].isLocked {
            var clips: [TimelineClip] = []
            clips.reserveCapacity(tracks[trackIndex].clips.count)
            for var clip in tracks[trackIndex].clips {
                if clip.timelineEnd <= start {
                    clips.append(clip)
                } else if clip.timelineStart >= end {
                    clip.timelineStart -= width
                    clips.append(clip)
                } else if clip.timelineStart < start, clip.timelineEnd > end {
                    // Spans the removed range: keep the head, continue the tail at the seam.
                    var head = clip
                    head.duration = start - clip.timelineStart
                    var tail = clip
                    tail.id = makeClipID()
                    tail.timelineStart = start
                    tail.sourceIn = clip.sourceIn + (end - clip.timelineStart)
                    tail.duration = clip.timelineEnd - end
                    clips.append(head)
                    clips.append(tail)
                } else if clip.timelineStart >= start, clip.timelineEnd <= end {
                    // Entirely inside the removed range: drop it.
                    continue
                } else if clip.timelineStart < start {
                    // Overlaps the range start: keep the head.
                    clip.duration = start - clip.timelineStart
                    clips.append(clip)
                } else {
                    // Overlaps the range end: keep the tail, moved to the seam.
                    let cut = end - clip.timelineStart
                    clip.sourceIn += cut
                    clip.duration -= cut
                    clip.timelineStart = start
                    clips.append(clip)
                }
            }
            tracks[trackIndex].clips = clips
        }
    }
}
