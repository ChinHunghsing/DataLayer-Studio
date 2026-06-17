import CoreGraphics
@testable import OverlayCore
import XCTest

final class OverlayPreviewRendererTests: XCTestCase {
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
