import XCTest
@testable import OverlayStudio

final class NumberTextFormatterTests: XCTestCase {
    func testParseDoubleTrimsWhitespaceAndAcceptsDecimals() {
        XCTAssertEqual(NumberTextFormatter.parseDouble(" 12.5 "), 12.5)
        XCTAssertEqual(NumberTextFormatter.parseDouble(""), nil)
    }

    func testParseIntRejectsFractionalAndOutOfRangeValues() {
        XCTAssertEqual(NumberTextFormatter.parseInt("42"), 42)
        XCTAssertEqual(NumberTextFormatter.parseInt("42.5"), nil)
        XCTAssertEqual(NumberTextFormatter.parseInt(""), nil)
        XCTAssertEqual(NumberTextFormatter.parseInt("999999999999999999999999"), nil)
    }

    func testFormattersProduceReadableValues() {
        XCTAssertEqual(NumberTextFormatter.parseDouble(NumberTextFormatter.formatDouble(12.34567)), 12.346)
        XCTAssertEqual(NumberTextFormatter.parseInt(NumberTextFormatter.formatInt(12000)), 12000)
    }
}
