import XCTest
@testable import OverlayStudio

final class TimecodeComponentsTests: XCTestCase {
    func testComponentOverflowAndUnderflowCarriesAcrossUnits() {
        XCTAssertEqual(
            TimecodeComponents(totalMilliseconds: 59_000).totalMilliseconds(replacing: .seconds, with: 60),
            60_000
        )
        XCTAssertEqual(
            TimecodeComponents(totalMilliseconds: 60_000).totalMilliseconds(replacing: .seconds, with: -1),
            59_000
        )
        XCTAssertEqual(
            TimecodeComponents(totalMilliseconds: 3_600_000).totalMilliseconds(replacing: .minutes, with: -1),
            3_540_000
        )
        XCTAssertEqual(
            TimecodeComponents(totalMilliseconds: 999).totalMilliseconds(replacing: .milliseconds, with: 1_000),
            1_000
        )
    }
}
