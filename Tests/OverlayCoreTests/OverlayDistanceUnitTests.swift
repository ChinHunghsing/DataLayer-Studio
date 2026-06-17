import OverlayCore
import XCTest

final class OverlayDistanceUnitTests: XCTestCase {
    func testFormatsKilometers() {
        XCTAssertEqual(OverlayDistanceUnit.kilometers.format(meters: 1234.56), "1.23")
    }

    func testFormatsMeters() {
        XCTAssertEqual(OverlayDistanceUnit.meters.format(meters: 1234.56), "1235")
    }

    func testFormatsMissingDistance() {
        XCTAssertEqual(OverlayDistanceUnit.kilometers.format(meters: nil), "--")
        XCTAssertEqual(OverlayDistanceUnit.meters.format(meters: .infinity), "--")
    }

    func testDistanceUnitCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(OverlayDistanceUnit.meters)
        let decoded = try JSONDecoder().decode(OverlayDistanceUnit.self, from: encoded)
        XCTAssertEqual(decoded, .meters)
    }
}
