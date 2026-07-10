import Accelerate
import AudioToolbox
import AVFoundation
import Foundation

enum AudioWaveformLoader {
    static let preferredSampleCount = 512

    static func loadPeaks(
        from url: URL,
        duration: TimeInterval,
        sampleCount: Int = preferredSampleCount
    ) async throws -> [Float] {
        guard duration.isFinite, duration > 0, sampleCount > 0 else { return [] }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? AudioWaveformError.couldNotStartReader
        }

        var peaks = [Float](repeating: 0, count: sampleCount)
        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            accumulate(
                sampleBuffer: sampleBuffer,
                duration: duration,
                peaks: &peaks
            )
        }

        if reader.status == .failed {
            throw reader.error ?? AudioWaveformError.readerFailed
        }
        return normalizedPeaks(peaks)
    }

    static func normalizedPeaks(_ peaks: [Float]) -> [Float] {
        guard let maximum = peaks.max(), maximum.isFinite, maximum > 0 else { return [] }
        return peaks.map { peak in
            guard peak.isFinite, peak > 0 else { return 0 }
            return min(1, sqrt(peak / maximum))
        }
    }

    private static func accumulate(
        sampleBuffer: CMSampleBuffer,
        duration: TimeInterval,
        peaks: inout [Float]
    ) {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              streamDescription.pointee.mSampleRate > 0 else {
            return
        }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let data = audioBufferList.mBuffers.mData else {
            return
        }

        let valueCount = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard valueCount > 0 else { return }
        let values = data.assumingMemoryBound(to: Float.self)
        let sampleRate = streamDescription.pointee.mSampleRate
        let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let bufferStart = presentationTime.isFinite ? presentationTime : 0

        var bufferPeak: Float = 0
        vDSP_maxmgv(values, 1, &bufferPeak, vDSP_Length(valueCount))
        guard bufferPeak.isFinite else { return }

        let bufferEnd = bufferStart + Double(frameCount) / sampleRate
        let startBucket = min(
            peaks.count - 1,
            max(0, Int(max(0, bufferStart) / duration * Double(peaks.count)))
        )
        let endBucket = min(
            peaks.count - 1,
            max(startBucket, Int(max(0, bufferEnd) / duration * Double(peaks.count)))
        )
        for bucket in startBucket...endBucket {
            peaks[bucket] = max(peaks[bucket], bufferPeak)
        }
    }
}

private enum AudioWaveformError: Error {
    case couldNotStartReader
    case readerFailed
}
