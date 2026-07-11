import AVFoundation
import Foundation

/// Assembles an `AVMutableComposition` from a timeline's resolved visible video segments: every
/// segment's video and audio land at its timeline position, and uncovered ranges stay empty so
/// playback and sample reading produce black frames and silence there.
///
/// Shared by `TimelineVideoWriter` (export) and the studio preview player so both read the same
/// clip geometry the same way.
public enum TimelineVideoCompositionBuilder {
    public static func make(
        project: TimelineProject,
        videoClips: [TimelineClip],
        requiredEnd: TimeInterval,
        renderSize requestedRenderSize: CGSize? = nil,
        framesPerSecond requestedFramesPerSecond: Double? = nil
    ) throws -> (
        composition: AVMutableComposition,
        videoRanges: [CMTimeRange],
        videoComposition: AVMutableVideoComposition
    ) {
        let composition = AVMutableComposition()
        let timescale = CMTimeScale(600)
        var videoRanges: [CMTimeRange] = []
        var videoInstructions: [AVMutableVideoCompositionInstruction] = []
        let renderSize = sanitizedRenderSize(
            requestedRenderSize ?? CGSize(width: project.outputWidth, height: project.outputHeight)
        )
        let framesPerSecond = sanitizedFramesPerSecond(
            requestedFramesPerSecond ?? project.framesPerSecond
        )

        for clip in videoClips {
            guard let videoAsset = project.asset(id: clip.assetID), videoAsset.kind == .video else {
                throw OverlayVideoError.invalidConfiguration("Timeline video clip references a missing video asset.")
            }
            let sourceAsset = AVURLAsset(url: videoAsset.url)
            guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
                throw OverlayVideoError.unreadableVideo("No video track found in \(videoAsset.url.path).")
            }
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw OverlayVideoError.writerFailed("Could not create timeline video composition track.")
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
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(
                aspectFitTransform(
                    naturalSize: sourceVideoTrack.naturalSize,
                    preferredTransform: sourceVideoTrack.preferredTransform,
                    renderSize: renderSize
                ),
                at: destinationStart
            )
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: destinationStart, duration: sourceDuration)
            instruction.layerInstructions = [layerInstruction]
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            videoInstructions.append(instruction)

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


        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            seconds: 1 / framesPerSecond,
            preferredTimescale: 60_000
        )
        videoComposition.instructions = instructionsFillingGaps(
            videoInstructions,
            requiredEnd: requiredEndTime
        )

        return (composition, videoRanges, videoComposition)
    }

    static func aspectFitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let scale = min(
            renderSize.width / max(1, displaySize.width),
            renderSize.height / max(1, displaySize.height)
        )
        let x = -transformedRect.minX * scale + (renderSize.width - displaySize.width * scale) / 2
        let y = -transformedRect.minY * scale + (renderSize.height - displaySize.height * scale) / 2
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    private static func instructionsFillingGaps(
        _ videoInstructions: [AVMutableVideoCompositionInstruction],
        requiredEnd: CMTime
    ) -> [AVVideoCompositionInstructionProtocol] {
        let sorted = videoInstructions.sorted { $0.timeRange.start < $1.timeRange.start }
        var result: [AVVideoCompositionInstructionProtocol] = []
        var cursor = CMTime.zero
        for instruction in sorted {
            if instruction.timeRange.start > cursor {
                result.append(blackInstruction(
                    start: cursor,
                    duration: CMTimeSubtract(instruction.timeRange.start, cursor)
                ))
            }
            result.append(instruction)
            cursor = maxTime(cursor, CMTimeRangeGetEnd(instruction.timeRange))
        }
        if requiredEnd > cursor {
            result.append(blackInstruction(start: cursor, duration: CMTimeSubtract(requiredEnd, cursor)))
        }
        return result
    }

    private static func blackInstruction(start: CMTime, duration: CMTime) -> AVMutableVideoCompositionInstruction {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: start, duration: duration)
        instruction.layerInstructions = []
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        return instruction
    }

    private static func sanitizedRenderSize(_ size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CGSize(width: 1_920, height: 1_080)
        }
        return size
    }

    private static func sanitizedFramesPerSecond(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 30
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private static func maxTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
    }
}
