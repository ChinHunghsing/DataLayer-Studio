@testable import OverlayCore
import XCTest

final class OverlayLayoutTests: XCTestCase {
    func testDefaultLayoutUsesDynamicElements() {
        let layout = OverlayLayout.default

        XCTAssertEqual(layout.elements.map(\.kind), [
            .topProgress,
            .speed,
            .pace,
            .distance,
            .heartRate,
            .cadence,
            .route,
            .timeDate
        ])
        XCTAssertTrue(layout.visibleElements.allSatisfy(\.frame.isVisible))
        XCTAssertEqual(layout.component(.speed).x, 0.025, accuracy: 0.0001)
        XCTAssertEqual(OverlayComponentID.topProgress.title, "Distance")
        XCTAssertEqual(OverlayComponentID.distance.title, "Distance value")
        XCTAssertEqual(OverlayComponentID.timeDate.title, "Time & Date")
        XCTAssertEqual(layout.elements.first { $0.kind == .topProgress }?.customization.valuePrecision, 1)
    }

    func testCanAddUpdateAndRemoveIndependentElements() {
        var layout = OverlayLayout.default
        let secondHeartRate = OverlayElement.defaultElement(
            kind: .heartRate,
            id: "heartRate-copy"
        )

        layout.elements.append(secondHeartRate)
        layout.updateElement(id: "heartRate-copy") { element in
            element.frame.x = 0.7
            element.customization.labelOverride = "ZONE"
            element.frame.isVisible = false
        }

        XCTAssertEqual(layout.elements.filter { $0.kind == .heartRate }.count, 2)
        XCTAssertEqual(layout.elements.first { $0.id == "heartRate-copy" }?.frame.x ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(layout.elements.first { $0.id == "heartRate-copy" }?.customization.labelOverride, "ZONE")
        XCTAssertFalse(layout.visibleElements.contains { $0.id == "heartRate-copy" })

        layout.removeElement(id: "heartRate-copy")
        XCTAssertEqual(layout.elements.filter { $0.kind == .heartRate }.count, 1)
    }

    func testLegacyComponentSetterUpdatesFirstMatchingElement() {
        var layout = OverlayLayout.default
        layout.speed = OverlayComponentFrame(x: 0.12, y: 0.34, scale: 1.4)

        XCTAssertEqual(layout.elements.first { $0.kind == .speed }?.frame.x ?? -1, 0.12, accuracy: 0.0001)
        XCTAssertEqual(layout.component(.speed).scale, 1.4, accuracy: 0.0001)
    }

    func testComponentFramesCanMoveOutsideCanvas() {
        var layout = OverlayLayout.default
        layout.updateElement(id: "route") { element in
            element.frame.x = -0.22
            element.frame.y = 1.18
        }

        let route = layout.elements.first { $0.id == "route" }
        XCTAssertEqual(route?.frame.x ?? 0, -0.22, accuracy: 0.0001)
        XCTAssertEqual(route?.frame.y ?? 0, 1.18, accuracy: 0.0001)
    }

    func testElementCustomizationStoresTypographyColorsAndLineWidth() {
        var layout = OverlayLayout.default
        layout.updateElement(id: "speed") { element in
            element.customization.showsPanel = false
            element.customization.showsIcon = true
            element.customization.iconOverride = "FAST"
            element.customization.labelFont = .avenirNextCondensedHeavy
            element.customization.valueFont = .futuraCondensedExtraBold
            element.customization.iconFont = .menloBold
            element.customization.labelColor = OverlayColor(red: 0.1, green: 0.2, blue: 0.3)
            element.customization.valueColor = OverlayColor(red: 0.8, green: 0.7, blue: 0.2)
            element.customization.iconColor = OverlayColor(red: 0.9, green: 0.1, blue: 0.1)
            element.customization.labelScale = 1.3
            element.customization.valueScale = 1.6
            element.customization.iconScale = 0.8
            element.customization.lineWidth = 18
            element.customization.lengthScale = 1.4
        }

        let speed = layout.elements.first { $0.id == "speed" }
        XCTAssertEqual(speed?.customization.showsPanel, false)
        XCTAssertEqual(speed?.customization.icon(default: "SPD"), "FAST")
        XCTAssertEqual(speed?.customization.labelFont, .avenirNextCondensedHeavy)
        XCTAssertEqual(speed?.customization.valueFont, .futuraCondensedExtraBold)
        XCTAssertEqual(speed?.customization.iconFont, .menloBold)
        XCTAssertEqual(speed?.customization.labelColor?.red ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.valueColor?.green ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.iconColor?.blue ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.labelScale ?? -1, 1.3, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.valueScale ?? -1, 1.6, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.iconScale ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.lineWidth ?? -1, 18, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.lengthScale ?? -1, 1.4, accuracy: 0.0001)
    }

    func testLayoutCodableRoundTrip() throws {
        var layout = OverlayLayout.default
        layout.updateElement(id: "route") { element in
            element.frame.x = -0.2
            element.frame.y = 1.14
            element.customization.lineWidth = 9
            element.customization.trackColor = OverlayColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 0.9)
        }
        layout.updateElement(id: "pace") { element in
            element.customization.valueFont = .futuraCondensedExtraBold
            element.customization.valuePrecision = 2
        }

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(OverlayLayout.self, from: data)

        XCTAssertEqual(decoded, layout)
    }
}
