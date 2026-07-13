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

    func testFormattersDoNotInsertThousandsSeparators() {
        XCTAssertEqual(NumberTextFormatter.formatInt(12000), "12000")
        XCTAssertEqual(NumberTextFormatter.formatDouble(12345.67, maximumFractionDigits: 2), "12345.67")
    }

    func testIntegerFieldDragAdjustsAndClampsValue() {
        XCTAssertEqual(IntegerTextField.draggedValue(base: 10, horizontalTranslation: 20, range: 0...100), 15)
        XCTAssertEqual(IntegerTextField.draggedValue(base: 98, horizontalTranslation: 20, range: 0...100), 100)
        XCTAssertEqual(IntegerTextField.draggedValue(base: 2, horizontalTranslation: -20, range: 0...100), 0)
    }
}
