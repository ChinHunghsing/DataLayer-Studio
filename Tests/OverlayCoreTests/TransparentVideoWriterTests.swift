import AVFoundation
import CoreMedia
@testable import OverlayCore
import XCTest

final class TransparentVideoWriterTests: XCTestCase {
    func testVideoErrorsExposeSpecificLocalizedDescription() {
        let error = OverlayVideoError.invalidConfiguration("Output bitrate must be positive.")

        XCTAssertEqual(error.localizedDescription, "Output bitrate must be positive.")
    }

    func testFractionalFrameRateDoesNotDriftOverLongExports() {
        let timing = TransparentVideoFrameTiming(framesPerSecond: 29.97, duration: 600)

        XCTAssertEqual(timing.frameCount, 17_982)
        XCTAssertEqual(CMTimeGetSeconds(timing.presentationTime(for: 17_982)), 600, accuracy: 0.00001)
    }

    func testFrameTimingSanitizesInvalidValues() {
        let timing = TransparentVideoFrameTiming(framesPerSecond: .nan, duration: -.infinity)

        XCTAssertEqual(timing.framesPerSecond, 1)
        XCTAssertEqual(timing.duration, 0)
        XCTAssertEqual(timing.frameCount, 1)
        XCTAssertFalse(timing.frameCountWasClamped)
        XCTAssertEqual(CMTimeGetSeconds(timing.presentationTime(for: -10)), 0, accuracy: 0.00001)
    }

    func testFrameTimingClampsOverflowingFrameCount() {
        let timing = TransparentVideoFrameTiming(
            framesPerSecond: .greatestFiniteMagnitude,
            duration: .greatestFiniteMagnitude
        )

        XCTAssertEqual(timing.frameCount, Int.max)
        XCTAssertTrue(timing.frameCountWasClamped)
    }

    func testWriterRejectsOverflowingFrameCountBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-overflow-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: .greatestFiniteMagnitude,
                duration: .greatestFiniteMagnitude
            )
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriterRejectsInvalidDurationBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 0
            )
        )
    }

    func testWriterRejectsInvalidBitrateBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 1,
                averageBitRate: 0
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: 30,
                duration: 1,
                averageBitRate: 1_000_000_001
            )
        )
    }

    func testWriterRejectsOddOutputDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1919,
                height: 1080,
                framesPerSecond: 30,
                duration: 1
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1920,
                height: 1079,
                framesPerSecond: 30,
                duration: 1
            )
        )
    }

    func testWriterRejectsOversizedOutputDimensionsBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 16_386,
                height: 1080,
                framesPerSecond: 30,
                duration: 1
            )
        )

        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 1920,
                height: 16_386,
                framesPerSecond: 30,
                duration: 1
            )
        )
    }

    func testWriterRejectsEncoderFrameRateOverflowBeforeExport() {
        assertWriterRejectsInvalidConfiguration(
            config: TransparentVideoWriterConfig(
                width: 2,
                height: 2,
                framesPerSecond: Double(Int.max) * 2,
                duration: Double.leastNormalMagnitude
            )
        )
    }

    func testWriterRejectsMissingOutputDirectoryBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-output-dir-\(UUID().uuidString)")
            .appendingPathComponent("overlay.mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(message.contains("Output directory does not exist"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriterRejectsDirectoryOutputPathBeforeExport() {
        let outputURL = FileManager.default.temporaryDirectory
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: []),
            config: validTinyConfig()
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(message.contains("Output path must be a file"))
        }
    }

    func testWriterRendersTinyHEVCAlphaOutputWhenEncoderIsAvailable() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-tiny-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
                TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 1,
                duration: 1
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.description.localizedCaseInsensitiveContains("encoder") {
            throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }

    private func assertWriterRejectsInvalidConfiguration(
        config: TransparentVideoWriterConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-invalid-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = TransparentVideoWriter(
            outputURL: outputURL,
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

    private func validTinyConfig() -> TransparentVideoWriterConfig {
        TransparentVideoWriterConfig(
            width: 2,
            height: 2,
            framesPerSecond: 1,
            duration: 1
        )
    }
}
