import AVFoundation
import Foundation

/// Assembles an `AVMutableComposition` from a timeline's video clips: every clip's video and
/// audio land at the clip's timeline position, and uncovered ranges stay empty so playback and
/// sample reading produce black frames and silence there.
///
/// Shared by `TimelineVideoWriter` (export) and the studio preview player so both read the same
/// clip geometry the same way.
public enum TimelineVideoCompositionBuilder {
    public static func make(
        project: TimelineProject,
        videoClips: [TimelineClip],
        requiredEnd: TimeInterval
    ) throws -> (composition: AVMutableComposition, videoRanges: [CMTimeRange]) {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OverlayVideoError.writerFailed("Could not create timeline video composition track.")
        }

        let timescale = CMTimeScale(600)
        var didSetPreferredTransform = false
        var videoRanges: [CMTimeRange] = []

        for clip in videoClips {
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let sourceAsset = AVURLAsset(url: videoAsset.url)
            guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(videoAsset.url.path).")
            }

            let sourceStart = CMTimeAdd(
                sourceVideoTrack.timeRange.start,
                CMTime(seconds: clip.sourceIn, preferredTimescale: timescale)
            )
            let sourceDuration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            let sourceEnd = CMTimeAdd(sourceStart, sourceDuration)
            let availableEnd = CMTimeRangeGetEnd(sourceVideoTrack.timeRange)
            guard sourceStart >= sourceVideoTrack.timeRange.start, sourceEnd <= availableEnd else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip extends past its source video duration.")
            }

            let destinationStart = CMTime(seconds: clip.timelineStart, preferredTimescale: timescale)
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: sourceStart, duration: sourceDuration),
                of: sourceVideoTrack,
                at: destinationStart
            )
            videoRanges.append(CMTimeRange(start: destinationStart, duration: sourceDuration))
            if !didSetPreferredTransform {
                compositionVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform
                didSetPreferredTransform = true
            }

            for sourceAudioTrack in sourceAsset.tracks(withMediaType: .audio) {
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }
                let audioStart = CMTimeAdd(
                    sourceAudioTrack.timeRange.start,
                    CMTime(seconds: clip.sourceIn, preferredTimescale: timescale)
                )
                let audioEnd = CMTimeAdd(audioStart, sourceDuration)
                let availableAudioEnd = CMTimeRangeGetEnd(sourceAudioTrack.timeRange)
                let audioDuration = minTime(sourceDuration, CMTimeSubtract(availableAudioEnd, audioStart))
                guard audioStart >= sourceAudioTrack.timeRange.start,
                      audioEnd > sourceAudioTrack.timeRange.start,
                      audioDuration > .zero else {
                    continue
                }
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: audioStart, duration: audioDuration),
                    of: sourceAudioTrack,
                    at: destinationStart
                )
            }
        }

        let requiredEndTime = CMTime(seconds: requiredEnd, preferredTimescale: timescale)
        if composition.duration < requiredEndTime {
            composition.insertEmptyTimeRange(
                CMTimeRange(
                    start: composition.duration,
                    duration: CMTimeSubtract(requiredEndTime, composition.duration)
                )
            )
        }

        return (composition, videoRanges)
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }
}
