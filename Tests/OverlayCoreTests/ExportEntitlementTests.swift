import AVFoundation
import CoreVideo
@testable import OverlayCore
import XCTest

final class ExportEntitlementTests: XCTestCase {
    func testFullEntitlementHasNoWatermarkAndKeepsSize() {
        XCTAssertNil(ExportEntitlement.full.watermarkText)

        let size = ExportEntitlement.full.clampedExportSize(width: 3840, height: 2160)
        XCTAssertEqual(size.width, 3840)
        XCTAssertEqual(size.height, 2160)
    }

    func testFreeEntitlementExposesWatermarkText() {
        XCTAssertEqual(ExportEntitlement.free.watermarkText, "Made with DataLayer Studio")
    }

    func testFreeEntitlementClampsLandscape4KTo1080p() {
        let size = ExportEntitlement.free.clampedExportSize(width: 3840, height: 2160)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }

    func testFreeEntitlementClampsPortrait4KTo1080p() {
        let size = ExportEntitlement.free.clampedExportSize(width: 2160, height: 3840)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
    }

    func testFreeEntitlementClamps1440pTo1080p() {
        let size = ExportEntitlement.free.clampedExportSize(width: 2560, height: 1440)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }

    func testFreeEntitlementClampsNonWidescreenByShortEdge() {
        let size = ExportEntitlement.free.clampedExportSize(width: 4000, height: 3000)
        XCTAssertEqual(size.width, 1440)
        XCTAssertEqual(size.height, 1080)
    }

    func testFreeEntitlementKeeps1080pAndSmallerSizes() {
        let fullHD = ExportEntitlement.free.clampedExportSize(width: 1920, height: 1080)
        XCTAssertEqual(fullHD.width, 1920)
        XCTAssertEqual(fullHD.height, 1080)

        let hd = ExportEntitlement.free.clampedExportSize(width: 1280, height: 720)
        XCTAssertEqual(hd.width, 1280)
        XCTAssertEqual(hd.height, 720)
    }

    func testFreeEntitlementProducesEvenDimensions() {
        let size = ExportEntitlement.free.clampedExportSize(width: 3839, height: 2161)
        XCTAssertEqual(size.width % 2, 0)
        XCTAssertEqual(size.height % 2, 0)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1920)
        XCTAssertLessThanOrEqual(min(size.width, size.height), 1080)
    }

    func testWatermarkDrawsPixelsInBottomRightCorner() throws {
        let buffer = try makeClearedPixelBuffer(width: 640, height: 360)

        ExportWatermarkRenderer.drawIfNeeded(.free, into: buffer)

        XCTAssertGreaterThan(
            maximumComponent(in: buffer, rows: 300..<360, columns: 320..<640),
            0,
            "Free-tier watermark should paint the bottom-right corner"
        )
        XCTAssertEqual(
            maximumComponent(in: buffer, rows: 0..<120, columns: 0..<320),
            0,
            "Watermark must stay in the corner and leave other regions transparent"
        )
    }

    func testFullEntitlementDrawsNoWatermark() throws {
        let buffer = try makeClearedPixelBuffer(width: 640, height: 360)

        ExportWatermarkRenderer.drawIfNeeded(.full, into: buffer)

        XCTAssertEqual(maximumComponent(in: buffer, rows: 0..<360, columns: 0..<640), 0)
    }

    func testFreeTransparentWriterClampsOutputTo1080p() async throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-free-clamp-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let writer = TransparentVideoWriter(
            outputURL: outputURL,
            series: TelemetrySeries(samples: [
                TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3)
            ]),
            config: TransparentVideoWriterConfig(
                width: 3840,
                height: 2160,
                framesPerSecond: 1,
                duration: 1,
                entitlement: .free
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError {
            switch error {
            case .unsupportedEncoder, .cannotStartWriter:
                throw XCTSkip("HEVC-with-alpha encoder is unavailable on this Mac: \(error.description)")
            default:
                throw error
            }
        }

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let naturalSize = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(Int(naturalSize.width.rounded()), 1920)
        XCTAssertEqual(Int(naturalSize.height.rounded()), 1080)
    }

    private func makeClearedPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    /// 逐字节扫描指定行列区域，返回最大分量值（0 表示区域完全透明）。
    /// 行号使用像素坐标（0 = 画面顶部）。
    private func maximumComponent(in pixelBuffer: CVPixelBuffer, rows: Range<Int>, columns: Range<Int>) -> UInt8 {
        CVPixelBufferLockBaseAddress(pixelBuffer, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, [.readOnly]) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        var maximum: UInt8 = 0
        for row in rows {
            for column in columns {
                for component in 0..<4 {
                    maximum = max(maximum, bytes[row * bytesPerRow + column * 4 + component])
                }
            }
        }
        return maximum
    }
}
