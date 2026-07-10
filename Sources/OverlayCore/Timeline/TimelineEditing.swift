import Foundation

// MARK: - Timeline clip editing (split / delete / ripple delete)
//
// Simplified DaVinci-style editing semantics for the timeline tab:
// - Splitting cuts every unlocked clip under a timeline time into two clips whose
//   source content stays continuous across the cut.
// - Removing a clip leaves a gap; gaps are legal timeline content (composited export
//   fills them with black frames, overlay-only export keeps them transparent).
// - Ripple-removing a clip also closes its time range on every unlocked track so
//   video and overlay stay in sync; clips spanning the range are trimmed or split.

extension TimelineProject {
    /// Minimum piece length produced by a split, matching the interactive trim floor.
    public static let minimumEditableClipDuration: TimeInterval = 0.1

    /// IDs of clips on unlocked tracks that `splitClips(atTimelineTime:)` would cut: the time
    /// must fall far enough inside the clip that both pieces keep the minimum duration.
    public func splittableClipIDs(atTimelineTime t: TimeInterval) -> [String] {
        guard t.isFinite else { return [] }
        return tracks
            .filter { !$0.isLocked }
            .flatMap(\.clips)
            .filter {
                t - $0.timelineStart >= Self.minimumEditableClipDuration
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
        makeClipID: () -> String = { UUID().uuidString }
    ) -> Int {
        let targets = Set(splittableClipIDs(atTimelineTime: t))
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
