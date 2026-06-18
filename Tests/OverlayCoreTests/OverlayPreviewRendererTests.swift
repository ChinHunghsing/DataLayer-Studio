import CoreGraphics
@testable import OverlayCore
import XCTest

final class OverlayPreviewRendererTests: XCTestCase {
    func testRendersRepeatedPreviewFramesAtSameSize() throws {
        let renderer = OverlayPreviewRenderer()
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
        ])

        let first = try renderer.renderOverlayImage(
            series: series,
            size: CGSize(width: 640, height: 360),
            videoTime: 0
        )
        let second = try renderer.renderOverlayImage(
            series: series,
            size: CGSize(width: 640, height: 360),
            videoTime: 1
        )

        XCTAssertEqual(first.width, 640)
        XCTAssertEqual(first.height, 360)
        XCTAssertEqual(second.width, 640)
        XCTAssertEqual(second.height, 360)
    }

    func testRejectsInvalidPreviewSizeBeforeRendering() {
        let renderer = OverlayPreviewRenderer()
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3)
        ])

        XCTAssertThrowsError(try renderer.renderOverlayImage(
            series: series,
            size: CGSize(width: CGFloat.nan, height: 1080),
            videoTime: 0
        )) { error in
            XCTAssertEqual(error as? OverlayPreviewError, .invalidPreviewSize)
        }

        XCTAssertThrowsError(try renderer.renderOverlayImage(
            series: series,
            size: CGSize(width: 1920, height: CGFloat.infinity),
            videoTime: 0
        )) { error in
            XCTAssertEqual(error as? OverlayPreviewError, .invalidPreviewSize)
        }

        XCTAssertThrowsError(try renderer.renderOverlayImage(
            series: series,
            size: CGSize(width: 16_385, height: 1080),
            videoTime: 0
        )) { error in
            XCTAssertEqual(error as? OverlayPreviewError, .invalidPreviewSize)
        }
    }
}
