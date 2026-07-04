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

    private static func removeTemporaryFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTinySourceVideo(at url: URL, frameCount: Int = 2) throws {
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
        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start tiny source writer.")
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let buffer = try makePixelBuffer(red: UInt8(80 + frameIndex * 40), green: 120, blue: 160)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: 2)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source frame.")
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source writer failed.")
        }
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
