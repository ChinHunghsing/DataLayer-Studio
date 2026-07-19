import XCTest
@testable import OverlayStudio

final class AppStoreUpdateCheckerTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() {
        XCTAssertTrue(AppStoreUpdateChecker.isNewer("2.10", than: "2.9"))
        XCTAssertFalse(AppStoreUpdateChecker.isNewer("2.9", than: "2.10"))
        XCTAssertFalse(AppStoreUpdateChecker.isNewer("2.10", than: "2.10"))
    }
}
