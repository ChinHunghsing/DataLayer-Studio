import Foundation

public enum TimelineExportValidationIssue: Error, Equatable, LocalizedError, Sendable {
    case invalidRange
    case missingOverlayClip
    case missingActivityAsset(clipID: String)
    case missingTelemetry(assetID: String)
    case missingVideoAsset(clipID: String)
    case invalidVideoSourceRange(clipID: String)

    public var errorDescription: String {
        switch self {
        case .invalidRange:
            return "Timeline export range must have a non-negative finite start and a positive finite duration."
        case .missingOverlayClip:
            return "Timeline export requires at least one enabled overlay clip."
        case let .missingActivityAsset(clipID):
            return "Timeline overlay clip \(clipID) references a missing activity asset."
        case let .missingTelemetry(assetID):
            return "Timeline activity asset \(assetID) has no loaded telemetry series."
        case let .missingVideoAsset(clipID):
            return "Timeline video clip \(clipID) references a missing video asset."
        case let .invalidVideoSourceRange(clipID):
            return "Timeline video clip \(clipID) extends outside its source video duration."
        }
    }
}

extension TimelineProject {
    /// Resolves the visible clip for every enabled track of `kind`, preserving the project's
    /// bottom-to-top track order. A track's last overlapping clip wins.
    public func activeClips(
        kind: TimelineTrack.Kind,
        atTimelineTime timelineTime: TimeInterval
    ) -> [TimelineClip] {
        tracks
            .filter { $0.kind == kind && $0.isEnabled }
            .compactMap { track in
                track.clips.last { $0.isEnabled && $0.contains(timelineTime: timelineTime) }
            }
    }

    public func enabledClips(kind: TimelineTrack.Kind) -> [TimelineClip] {
        tracks
            .filter { $0.kind == kind && $0.isEnabled }
            .flatMap(\.clips)
            .filter(\.isEnabled)
    }

    /// Time ranges for DaVinci-style "individual clips" rendering: one range per enabled clip of
    /// `kind`, intersected with the export range and sorted by start time. Ranges from clips on
    /// different tracks may overlap; exact duplicates are merged. Slivers shorter than the
    /// interactive minimum clip duration (left when the export in/out cuts through a clip edge)
    /// are dropped.
    public func individualClipExportRanges(
        kind: TimelineTrack.Kind,
        timelineStart: TimeInterval,
        duration: TimeInterval
    ) -> [(start: TimeInterval, duration: TimeInterval)] {
        guard timelineStart.isFinite, duration.isFinite, duration > 0 else { return [] }
        let rangeEnd = timelineStart + duration

        var seen = Set<String>()
        return enabledClips(kind: kind)
            .compactMap { clip -> (start: TimeInterval, duration: TimeInterval)? in
                let start = max(clip.timelineStart, timelineStart)
                let end = min(clip.timelineEnd, rangeEnd)
                guard end - start >= Self.minimumEditableClipDuration else { return nil }
                return (start, end - start)
            }
            .sorted { lhs, rhs in
                lhs.start != rhs.start ? lhs.start < rhs.start : lhs.duration < rhs.duration
            }
            .filter { range in
                seen.insert("\(range.start)-\(range.duration)").inserted
            }
    }

    public func firstExportValidationIssue(
        mode: OverlayExportMode,
        timelineStart: TimeInterval,
        duration: TimeInterval,
        availableTelemetryAssetIDs: Set<String>
    ) -> TimelineExportValidationIssue? {
        guard timelineStart.isFinite,
              timelineStart >= 0,
              duration.isFinite,
              duration > 0,
              (timelineStart + duration).isFinite else {
            return .invalidRange
        }

        let overlayClips = enabledClips(kind: .overlay)
        guard !overlayClips.isEmpty else {
            return .missingOverlayClip
        }
        for clip in overlayClips {
            guard let asset = asset(id: clip.assetID), asset.kind == .activity else {
                return .missingActivityAsset(clipID: clip.id)
            }
            guard availableTelemetryAssetIDs.contains(asset.id) else {
                return .missingTelemetry(assetID: asset.id)
            }
        }

        guard mode == .video else { return nil }
        do {
            _ = try validatedVideoClipsForExport(timelineStart: timelineStart, duration: duration)
            return nil
        } catch let issue as TimelineExportValidationIssue {
            return issue
        } catch {
            return .invalidRange
        }
    }

    /// Validates every enabled source clip, then resolves the visible video into non-overlapping
    /// segments. Tracks are stored bottom-to-top, so the last active video track covers those below.
    public func validatedVideoClipsForExport(
        timelineStart: TimeInterval,
        duration: TimeInterval
    ) throws -> [TimelineClip] {
        guard timelineStart.isFinite,
              timelineStart >= 0,
              duration.isFinite,
              duration > 0,
              (timelineStart + duration).isFinite else {
            throw TimelineExportValidationIssue.invalidRange
        }

        let end = timelineStart + duration
        let epsilon = 1e-6
        let relevantClips = enabledClips(kind: .video)
            .filter { $0.timelineEnd > timelineStart + epsilon && $0.timelineStart < end - epsilon }

        for clip in relevantClips {
            guard let videoAsset = asset(id: clip.assetID), videoAsset.kind == .video else {
                throw TimelineExportValidationIssue.missingVideoAsset(clipID: clip.id)
            }
            guard clip.timelineStart.isFinite,
                  clip.timelineStart >= 0,
                  clip.sourceIn.isFinite,
                  clip.sourceIn >= 0,
                  clip.duration.isFinite,
                  clip.duration > 0,
                  videoAsset.duration.isFinite,
                  clip.sourceIn + clip.duration <= videoAsset.duration + epsilon else {
                throw TimelineExportValidationIssue.invalidVideoSourceRange(clipID: clip.id)
            }
        }

        var boundaries = [timelineStart, end]
        for clip in relevantClips {
            boundaries.append(max(timelineStart, clip.timelineStart))
            boundaries.append(min(end, clip.timelineEnd))
        }
        boundaries.sort()
        var uniqueBoundaries: [TimeInterval] = []
        for boundary in boundaries where uniqueBoundaries.last.map({ abs($0 - boundary) > epsilon }) ?? true {
            uniqueBoundaries.append(boundary)
        }

        var resolved: [(sourceClipID: String, clip: TimelineClip)] = []
        var segmentCountBySourceClipID: [String: Int] = [:]
        for index in 0..<(max(0, uniqueBoundaries.count - 1)) {
            let segmentStart = uniqueBoundaries[index]
            let segmentEnd = uniqueBoundaries[index + 1]
            let segmentDuration = segmentEnd - segmentStart
            guard segmentDuration > epsilon else { continue }

            let sampleTime = segmentStart + segmentDuration / 2
            guard let visibleClip = activeClips(kind: .video, atTimelineTime: sampleTime).last else {
                continue
            }
            let segmentSourceIn = visibleClip.sourceTime(atTimelineTime: segmentStart)

            if let lastIndex = resolved.indices.last,
               resolved[lastIndex].sourceClipID == visibleClip.id,
               abs(resolved[lastIndex].clip.timelineEnd - segmentStart) <= epsilon,
               abs(resolved[lastIndex].clip.sourceIn + resolved[lastIndex].clip.duration - segmentSourceIn) <= epsilon {
                resolved[lastIndex].clip.duration += segmentDuration
                continue
            }

            let segmentIndex = segmentCountBySourceClipID[visibleClip.id, default: 0]
            segmentCountBySourceClipID[visibleClip.id] = segmentIndex + 1
            var segment = visibleClip
            segment.id = segmentIndex == 0
                ? visibleClip.id
                : "\(visibleClip.id).visible.\(segmentIndex)"
            segment.timelineStart = segmentStart
            segment.sourceIn = segmentSourceIn
            segment.duration = segmentDuration
            resolved.append((visibleClip.id, segment))
        }

        return resolved.map(\.clip)
    }
}
