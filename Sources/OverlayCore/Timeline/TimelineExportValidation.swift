import Foundation

public enum TimelineExportValidationIssue: Error, Equatable, LocalizedError, Sendable {
    case invalidRange
    case missingOverlayClip
    case missingActivityAsset(clipID: String)
    case missingTelemetry(assetID: String)
    case missingVideoClip
    case missingVideoAsset(clipID: String)
    case invalidVideoSourceRange(clipID: String)
    case videoRangeStartsInGap
    case videoGap(previousClipID: String, nextClipID: String)
    case videoOverlap(previousClipID: String, nextClipID: String)
    case videoRangeNotFullyCovered

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
        case .missingVideoClip:
            return "Timeline video export requires at least one enabled video clip."
        case let .missingVideoAsset(clipID):
            return "Timeline video clip \(clipID) references a missing video asset."
        case let .invalidVideoSourceRange(clipID):
            return "Timeline video clip \(clipID) extends outside its source video duration."
        case .videoRangeStartsInGap:
            return "Timeline video export range starts in a gap between video clips."
        case .videoGap:
            return "Timeline video export range contains a gap between video clips."
        case .videoOverlap:
            return "Timeline video export does not support overlapping video clips."
        case .videoRangeNotFullyCovered:
            return "Timeline video export range is not fully covered by enabled video clips."
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
            .compactMap { $0.clip(atTimelineTime: timelineTime) }
    }

    public func enabledClips(kind: TimelineTrack.Kind) -> [TimelineClip] {
        tracks
            .filter { $0.kind == kind && $0.isEnabled }
            .flatMap(\.clips)
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
            return .videoRangeNotFullyCovered
        }
    }

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
            .sorted { lhs, rhs in
                if abs(lhs.timelineStart - rhs.timelineStart) > epsilon {
                    return lhs.timelineStart < rhs.timelineStart
                }
                return lhs.id < rhs.id
            }

        guard !relevantClips.isEmpty else {
            throw TimelineExportValidationIssue.missingVideoClip
        }

        var coveredUntil = timelineStart
        var coveringClips: [TimelineClip] = []
        for (index, clip) in relevantClips.enumerated() {
            if index == 0 {
                guard clip.timelineStart <= timelineStart + epsilon else {
                    throw TimelineExportValidationIssue.videoRangeStartsInGap
                }
            } else if let previousClip = coveringClips.last {
                if clip.timelineStart > coveredUntil + epsilon {
                    throw TimelineExportValidationIssue.videoGap(
                        previousClipID: previousClip.id,
                        nextClipID: clip.id
                    )
                }
                if clip.timelineStart < coveredUntil - epsilon {
                    throw TimelineExportValidationIssue.videoOverlap(
                        previousClipID: previousClip.id,
                        nextClipID: clip.id
                    )
                }
            }

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

            coveringClips.append(clip)
            coveredUntil = max(coveredUntil, clip.timelineEnd)
            if coveredUntil >= end - epsilon {
                return coveringClips
            }
        }

        throw TimelineExportValidationIssue.videoRangeNotFullyCovered
    }
}
