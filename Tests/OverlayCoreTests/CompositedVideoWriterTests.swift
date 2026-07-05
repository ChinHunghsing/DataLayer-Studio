import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import XCTest

final class CompositedVideoWriterTests: XCTestCase {
    func testWriterRendersTinyCompositedOutput() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-output-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 1, distanceMeters: 3)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        do {
            let asset = AVURLAsset(url: outputURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            XCTAssertEqual(tracks.count, 1)
        }
    }

    func testWriterRendersTrimmedCompositedOutput() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-trimmed-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited-trimmed-output-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // MARK: - Configuration rejection

    func testWriterRejectsInvalidDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 0, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_919, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_920, height: 1_079))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 16_386, height: 1_080))
        assertWriterRejectsInvalidConfiguration(makeConfig(width: 1_920, height: 16_386))
    }

    func testWriterRejectsInvalidTimingBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(framesPerSecond: .nan))
        assertWriterRejectsInvalidConfiguration(makeConfig(framesPerSecond: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(startTime: -1))
        assertWriterRejectsInvalidConfiguration(makeConfig(startTime: .infinity))
        assertWriterRejectsInvalidConfiguration(makeConfig(duration: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(duration: .infinity))
    }

    func testWriterRejectsInvalidBitrateBeforeExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(averageBitRate: 0))
        assertWriterRejectsInvalidConfiguration(makeConfig(averageBitRate: 1_000_000_001))
    }

    func testWriterRejectsAlphaCodecForCompositedExport() {
        assertWriterRejectsInvalidConfiguration(makeConfig(codec: .hevcAlpha))
        assertWriterRejectsInvalidConfiguration(makeConfig(codec: .proRes4444))
    }

    func testWriterRejectsOverflowingFrameCountBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            makeConfig(framesPerSecond: .greatestFiniteMagnitude, duration: .greatestFiniteMagnitude)
        )
    }

    // MARK: - Trim and overlay correctness

    func testTrimExportSelectsSourceFramesAtStartTime() async throws {
        let sourceURL = temporaryMovieURL("composited-trim-luma-source")
        let outputURL = temporaryMovieURL("composited-trim-luma-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        // First half of the source is black, second half is white, so the decoded
        // luma of output frame 0 tells us which source frame the trim landed on.
        try makeTinySourceVideo(at: sourceURL, frameCount: 4) { index in
            index < 2 ? (0, 0, 0) : (255, 255, 255)
        }

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 0.5,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertGreaterThan(
            luma.mean,
            150,
            "Trim starting at 1s should land on the white source frames, not the leading black frames."
        )
    }

    func testExportBurnsOverlayOntoSourceFrames() async throws {
        let sourceURL = temporaryMovieURL("composited-overlay-source")
        let outputURL = temporaryMovieURL("composited-overlay-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        // Fully black source so any bright pixel in the output must come from the overlay.
        try makeTinySourceVideo(at: sourceURL, frameCount: 2) { _ in (0, 0, 0) }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.25, y: 0.4, scale: 1.6)
        element.customization.showsPanel = false
        element.customization.valueColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.labelColor = OverlayColor(red: 1, green: 1, blue: 1)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
                TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
            ]),
            config: CompositedVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [element])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertGreaterThan(
            luma.max,
            120,
            "A black source with a white overlay must produce bright pixels once the overlay is composited."
        )
    }

    // MARK: - Audio passthrough

    func testExportKeepsSourceAudioTrack() async throws {
        let sourceURL = temporaryMovieURL("composited-audio-source")
        let outputURL = temporaryMovieURL("composited-audio-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 2,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioDuration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(CMTimeGetSeconds(audioDuration), 2, accuracy: 0.15)
    }

    func testTrimExportAlignsSourceAudioToStartTime() async throws {
        let sourceURL = temporaryMovieURL("composited-audio-trim-source")
        let outputURL = temporaryMovieURL("composited-audio-trim-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL, frameCount: 4, includeAudio: true)

        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: sourceURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0),
                TelemetrySample(elapsed: 2, distanceMeters: 6)
            ]),
            config: CompositedVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                startTime: 1,
                duration: 1,
                averageBitRate: 200_000,
                codec: .h264,
                overlayLayout: OverlayLayout(elements: [])
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableCompositedTestEncoder {
            throw XCTSkip("Composited video encoder is unavailable on this Mac: \(error.description)")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioDuration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(
            CMTimeGetSeconds(audioDuration),
            1,
            accuracy: 0.15,
            "A 1s window starting 1s into a 2s source must keep 1s of aligned audio."
        )
    }

    // MARK: - Helpers

    private func makeConfig(
        width: Int = 64,
        height: Int = 64,
        framesPerSecond: Double = 2,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 1,
        averageBitRate: Int = 200_000,
        codec: OverlayVideoCodec = .h264
    ) -> CompositedVideoWriterConfig {
        CompositedVideoWriterConfig(
            width: width,
            height: height,
            framesPerSecond: framesPerSecond,
            startTime: startTime,
            duration: duration,
            averageBitRate: averageBitRate,
            codec: codec,
            overlayLayout: OverlayLayout(elements: [])
        )
    }

    private func assertWriterRejectsInvalidConfiguration(
        _ config: CompositedVideoWriterConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Point at a real (existing) output directory so the dedicated validation
        // rule fails first, not the output-URL existence check. The source video
        // is never read because validation runs before any file access.
        let outputURL = temporaryMovieURL("composited-invalid")
        let writer = CompositedVideoWriter(
            outputURL: outputURL,
            sourceVideoURL: temporaryMovieURL("composited-missing-source"),
            series: TelemetrySeries(samples: []),
            config: config
        )

        XCTAssertThrowsError(try writer.write(), file: file, line: line) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)", file: file, line: line)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), file: file, line: line)
    }

    private func temporaryMovieURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private func firstFrameLuma(from url: URL) async throws -> (max: Double, mean: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)

        var maxLuma = 0.0
        var sumLuma = 0.0
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                maxLuma = max(maxLuma, luma)
                sumLuma += luma
            }
        }
        return (maxLuma, sumLuma / Double(width * height))
    }

    private static func removeTemporaryFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTinySourceVideo(
        at url: URL,
        frameCount: Int = 2,
        framesPerSecond: Int32 = 2,
        includeAudio: Bool = false,
        frameColor: (Int) -> (red: UInt8, green: UInt8, blue: UInt8) = { index in
            (UInt8(80 + index * 40), 120, 160)
        }
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder("Could not create tiny source video input.")
        }
        writer.add(input)

        let sampleRate = 44_100.0
        let totalDuration = Double(frameCount) / Double(framesPerSecond)
        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let newInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            newInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(newInput) else {
                throw OverlayVideoError.unsupportedEncoder("Could not create tiny source audio input.")
            }
            writer.add(newInput)
            audioInput = newInput
        }

        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start tiny source writer.")
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let color = frameColor(frameIndex)
            let buffer = try makePixelBuffer(red: color.red, green: color.green, blue: color.blue)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source frame.")
            }
        }
        input.markAsFinished()

        if let audioInput {
            let sampleBuffer = try makeSilentAudioSampleBuffer(durationSeconds: totalDuration, sampleRate: sampleRate)
            while !audioInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard audioInput.append(sampleBuffer) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source audio.")
            }
            audioInput.markAsFinished()
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source writer failed.")
        }
    }

    private func makeSilentAudioSampleBuffer(durationSeconds: Double, sampleRate: Double) throws -> CMSampleBuffer {
        let sampleCount = Int(sampleRate * durationSeconds)
        let bytesPerSample = 2
        let dataSize = sampleCount * bytesPerSample

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerSample),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio format description.")
        }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else {
            throw OverlayVideoError.writerFailed("Could not allocate tiny source audio block buffer.")
        }
        guard CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        ) == noErr else {
            throw OverlayVideoError.writerFailed("Could not zero-fill tiny source audio block buffer.")
        }

        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio sample buffer.")
        }
        return sampleBuffer
    }

    private func makePixelBuffer(red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}

private extension OverlayVideoError {
    var isUnavailableCompositedTestEncoder: Bool {
        switch self {
        case .unsupportedEncoder, .cannotStartWriter:
            return true
        case let .writerFailed(message):
            return message.localizedCaseInsensitiveContains("encoder") || message.contains("-12903")
        case .unreadableVideo,
             .cannotCreatePixelBuffer,
             .cannotCreateBitmapContext,
             .invalidConfiguration,
             .cancelled:
            return false
        }
    }
}
