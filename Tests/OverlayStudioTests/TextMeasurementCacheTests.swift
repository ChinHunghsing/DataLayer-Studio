import XCTest
import OverlayCore
@testable import OverlayStudioKit

final class TextMeasurementCacheTests: XCTestCase {
    override func tearDown() {
        TextMeasurementCache.clear()
        super.tearDown()
    }

    func testCachesRepeatedTextWidthMeasurements() {
        TextMeasurementCache.clear()

        let firstWidth = TextMeasurementCache.width("PACE", size: 16, fontName: .helveticaNeueBold)
        let secondWidth = TextMeasurementCache.width("PACE", size: 16, fontName: .helveticaNeueBold)

        XCTAssertGreaterThan(firstWidth, 0)
        XCTAssertEqual(firstWidth, secondWidth)
        XCTAssertEqual(TextMeasurementCache.cachedWidthCount, 1)
    }

    func testNormalizesInvalidFontSizeBeforeCaching() {
        TextMeasurementCache.clear()

        let invalidWidth = TextMeasurementCache.width("DIST", size: .nan, fontName: .menloBold)
        let fallbackWidth = TextMeasurementCache.width("DIST", size: 12, fontName: .menloBold)

        XCTAssertEqual(invalidWidth, fallbackWidth)
        XCTAssertEqual(TextMeasurementCache.cachedWidthCount, 1)
    }
}
