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
        let topProgress = layout.elements.first { $0.kind == .topProgress }
        XCTAssertEqual(topProgress?.customization.valuePrecision, 1)
        XCTAssertEqual(topProgress?.customization.showsPanel, false)
        XCTAssertEqual(topProgress?.customization.lineWidth ?? -1, 6, accuracy: 0.0001)
        XCTAssertEqual(topProgress?.customization.progressInsetScale ?? -1, 0.82, accuracy: 0.0001)
        XCTAssertEqual(topProgress?.customization.progressKnobScale ?? -1, 0.86, accuracy: 0.0001)
        XCTAssertEqual(topProgress?.customization.progressValueMarginScale ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(topProgress?.customization.progressTickCount, 48)
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

    func testWeatherIconMapsCommonOpenWeatherSummaries() {
        XCTAssertTrue(OverlayElement.defaultElement(kind: .weather).customization.showsIcon)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Clear"), .clear)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Clouds"), .clouds)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Rain"), .rain)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Snow"), .snow)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Thunderstorm"), .thunderstorm)
        XCTAssertEqual(OverlayWeatherIcon.icon(for: "Fog"), .fog)
    }

    func testCanMoveElementLayerOrder() {
        var layout = OverlayLayout.default

        layout.moveElement(id: "speed", by: 1)
        XCTAssertEqual(layout.elements.map(\.id).prefix(3), ["topProgress", "pace", "speed"])

        layout.moveElement(id: "speed", by: -2)
        XCTAssertEqual(layout.elements.map(\.id).prefix(3), ["speed", "topProgress", "pace"])

        layout.moveElement(id: "speed", by: -1)
        XCTAssertEqual(layout.elements.first?.id, "speed")

        layout.moveElement(id: "speed", by: 99)
        XCTAssertEqual(layout.elements.last?.id, "speed")
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
            element.customization.showsPanelBorder = false
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
            element.customization.progressInsetScale = 1.2
            element.customization.progressKnobScale = 1.6
            element.customization.progressValueMarginScale = 2.2
            element.customization.progressTickCount = 36
        }

        let speed = layout.elements.first { $0.id == "speed" }
        XCTAssertEqual(speed?.customization.showsPanel, false)
        XCTAssertEqual(speed?.customization.panelBorderIsVisible, false)
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
        XCTAssertEqual(speed?.customization.progressInsetScale ?? -1, 1.2, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.progressKnobScale ?? -1, 1.6, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.progressValueMarginScale ?? -1, 2.2, accuracy: 0.0001)
        XCTAssertEqual(speed?.customization.progressTickCount, 36)
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
        layout.updateElement(id: "topProgress") { element in
            element.customization.progressInsetScale = 0.4
            element.customization.progressKnobScale = 1.7
            element.customization.progressValueMarginScale = 2.4
            element.customization.progressTickCount = 72
        }

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(OverlayLayout.self, from: data)

        XCTAssertEqual(decoded, layout)
    }

    func testSanitizedLayoutClampsUnsafeImportedValues() {
        let layout = OverlayLayout(
            elements: [
                OverlayElement(
                    id: "duplicate",
                    kind: .speed,
                    frame: OverlayComponentFrame(
                        x: .infinity,
                        y: -.infinity,
                        scale: .nan,
                        style: OverlayComponentStyle(panelOpacity: .infinity, textScale: .nan)
                    ),
                    customization: OverlayElementCustomization(
                        valuePrecision: 99,
                        gaugeMinimum: 20,
                        gaugeMaximum: 5,
                        labelColor: OverlayColor(red: .nan, green: 2, blue: -4, alpha: .infinity),
                        lineWidth: .infinity,
                        lengthScale: -.infinity,
                        progressInsetScale: 9,
                        progressKnobScale: -2,
                        progressValueMarginScale: 99,
                        progressTickCount: 999,
                        labelScale: .nan
                    )
                ),
                OverlayElement(
                    id: "duplicate",
                    kind: .route,
                    frame: OverlayComponentFrame(x: 0.5, y: 0.5)
                ),
                OverlayElement(
                    id: " ",
                    kind: .timeDate,
                    frame: OverlayComponentFrame(x: 0.2, y: 0.2)
                )
            ],
            style: OverlayStyle(panelOpacity: .nan, metricScale: .infinity)
        )

        let sanitized = layout.sanitized
        let speed = sanitized.elements[0]

        XCTAssertEqual(speed.frame.x, 0, accuracy: 0.0001)
        XCTAssertEqual(speed.frame.y, 0, accuracy: 0.0001)
        XCTAssertEqual(speed.frame.scale, 1, accuracy: 0.0001)
        XCTAssertNil(speed.frame.style.panelOpacity)
        XCTAssertEqual(speed.frame.style.textScale, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.valuePrecision, 3)
        XCTAssertEqual(speed.customization.gaugeMinimum ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.gaugeMaximum ?? -1, 21, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.labelColor?.red ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.labelColor?.green ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.labelColor?.blue ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.labelColor?.alpha ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.lineWidth, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.lengthScale, 1, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.progressInsetScale ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.progressKnobScale ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.progressValueMarginScale ?? -1, 4, accuracy: 0.0001)
        XCTAssertEqual(speed.customization.progressTickCount, 160)
        XCTAssertEqual(speed.customization.labelScale, 1, accuracy: 0.0001)
        XCTAssertEqual(sanitized.style.panelOpacity, 0.64, accuracy: 0.0001)
        XCTAssertEqual(sanitized.style.metricScale, 1, accuracy: 0.0001)
        XCTAssertEqual(Set(sanitized.elements.map(\.id)).count, sanitized.elements.count)
        XCTAssertFalse(sanitized.elements.contains { $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testUpdateElementSanitizesMutationResult() {
        var layout = OverlayLayout.default

        layout.updateElement(id: "pace") { element in
            element.frame.x = .infinity
            element.frame.y = -2
            element.frame.scale = .nan
            element.customization.valueScale = .infinity
            element.customization.lineWidth = -.infinity
        }

        let pace = layout.elements.first { $0.id == "pace" }
        XCTAssertEqual(pace?.frame.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(pace?.frame.y ?? 0, -1, accuracy: 0.0001)
        XCTAssertEqual(pace?.frame.scale ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(pace?.customization.valueScale ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(pace?.customization.lineWidth ?? -1, 1, accuracy: 0.0001)
    }

    func testRenderConfigSanitizesLayout() {
        let unsafeLayout = OverlayLayout(
            elements: [
                OverlayElement(
                    id: "speed",
                    kind: .speed,
                    frame: OverlayComponentFrame(x: .infinity, y: .nan, scale: -.infinity)
                )
            ],
            style: OverlayStyle(panelOpacity: .nan)
        )

        let config = OverlayRenderConfig(size: CGSize(width: 1920, height: 1080), layout: unsafeLayout)
        let speed = config.layout.elements.first

        XCTAssertEqual(speed?.frame.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(speed?.frame.y ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(speed?.frame.scale ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(config.layout.style.panelOpacity, 0.64, accuracy: 0.0001)
    }
}
