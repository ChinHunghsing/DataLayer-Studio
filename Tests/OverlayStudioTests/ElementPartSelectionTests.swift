import XCTest
import OverlayCore
@testable import OverlayStudio

@MainActor
final class ElementPartSelectionTests: XCTestCase {
    private func makeModel() -> (StudioModel, [String]) {
        let model = StudioModel()
        let ids = model.layout.visibleElements.map(\.id)
        return (model, ids)
    }

    func testFirstTapSelectsElementWithoutPart() {
        let (model, ids) = makeModel()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }
        // The model preselects an element at launch; tap one that is not selected yet
        // so this exercises the first-click path.
        guard let targetID = ids.first(where: { $0 != model.selectedElementID }) else {
            return XCTFail("needs an unselected element")
        }

        model.handleCanvasElementTap(id: targetID, part: .value)
        XCTAssertEqual(model.selectedElementID, targetID)
        XCTAssertNil(model.selectedElementPart)
    }

    func testSecondTapOnSameElementSelectsPart() {
        let (model, ids) = makeModel()
        guard let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs a metric element")
        }

        model.handleCanvasElementTap(id: metricID, part: .value)
        model.handleCanvasElementTap(id: metricID, part: .value)
        XCTAssertEqual(model.selectedElementPart, .value)
    }

    func testSecondTapOutsidePartZonesClearsPart() {
        let (model, _) = makeModel()
        guard let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs a metric element")
        }

        model.handleCanvasElementTap(id: metricID, part: .value)
        model.handleCanvasElementTap(id: metricID, part: .value)
        XCTAssertEqual(model.selectedElementPart, .value)

        model.handleCanvasElementTap(id: metricID, part: nil)
        XCTAssertNil(model.selectedElementPart)
        XCTAssertEqual(model.selectedElementID, metricID)
    }

    func testTapOnOtherElementClearsPart() {
        let (model, ids) = makeModel()
        guard ids.count >= 2, let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs 2 elements incl. a metric one")
        }
        let otherID = ids.first { $0 != metricID }!

        model.handleCanvasElementTap(id: metricID, part: .value)
        model.handleCanvasElementTap(id: metricID, part: .value)
        model.handleCanvasElementTap(id: otherID, part: nil)

        XCTAssertEqual(model.selectedElementID, otherID)
        XCTAssertNil(model.selectedElementPart)
    }

    func testHiddenPartCannotBeSelected() {
        let (model, _) = makeModel()
        guard let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs a metric element")
        }
        model.updateElement(metricID) { $0.customization.showsIcon = false }

        model.handleCanvasElementTap(id: metricID, part: nil)
        model.handleCanvasElementTap(id: metricID, part: .icon)
        XCTAssertNil(model.selectedElementPart)

        model.updateElement(metricID) { $0.customization.showsIcon = true }
        model.handleCanvasElementTap(id: metricID, part: .icon)
        XCTAssertEqual(model.selectedElementPart, .icon)
    }

    func testEscapeStepsPartThenElement() {
        let (model, _) = makeModel()
        guard let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs a metric element")
        }

        model.handleCanvasElementTap(id: metricID, part: nil)
        model.handleCanvasElementTap(id: metricID, part: .value)
        XCTAssertEqual(model.selectedElementPart, .value)

        model.escapeCanvasSelection()
        XCTAssertNil(model.selectedElementPart)
        XCTAssertEqual(model.selectedElementID, metricID)

        model.escapeCanvasSelection()
        XCTAssertNil(model.selectedElementID)
        XCTAssertTrue(model.selectedElementIDs.isEmpty)
    }

    func testMultiSelectionClearsPart() {
        let (model, ids) = makeModel()
        guard ids.count >= 2, let metricID = firstMetricElementID(model) else {
            return XCTFail("default layout needs 2 elements incl. a metric one")
        }
        let otherID = ids.first { $0 != metricID }!

        model.handleCanvasElementTap(id: metricID, part: nil)
        model.handleCanvasElementTap(id: metricID, part: .value)
        XCTAssertEqual(model.selectedElementPart, .value)

        model.toggleElementInSelection(id: otherID)
        XCTAssertNil(model.selectedElementPart)
    }

    func testPartRectsCoverAvailablePartsForMetricElement() {
        let (model, _) = makeModel()
        guard let metricID = firstMetricElementID(model),
              let element = model.layout.elements.first(where: { $0.id == metricID }) else {
            return XCTFail("default layout needs a metric element")
        }

        let geometry = CanvasElementGeometry(model: model)
        let rects = geometry.partRects(element: element, alignedMetricWidth: nil)
        let container = geometry.unitRect(element: element, alignedMetricWidth: nil)

        for part in OverlayElementPart.availableParts(for: element) {
            guard let rect = rects[part] else {
                return XCTFail("missing part rect for \(part.rawValue)")
            }
            XCTAssertTrue(
                container.insetBy(dx: -1e-6, dy: -1e-6).contains(rect),
                "\(part.rawValue) zone escapes the element rect"
            )
            let center = CGPoint(x: rect.midX, y: rect.midY)
            XCTAssertEqual(
                geometry.part(at: center, element: element, alignedMetricWidth: nil),
                part,
                "zone center should hit-test to its own part"
            )
        }
    }

    func testAvailablePartsFollowVisibilityToggles() {
        let (model, _) = makeModel()
        guard let metricID = firstMetricElementID(model),
              var element = model.layout.elements.first(where: { $0.id == metricID }) else {
            return XCTFail("default layout needs a metric element")
        }

        element.customization.showsLabel = true
        element.customization.showsUnit = true
        element.customization.showsIcon = true
        XCTAssertEqual(OverlayElementPart.availableParts(for: element), [.label, .value, .unit, .icon])

        element.customization.showsLabel = false
        element.customization.showsUnit = false
        element.customization.showsIcon = false
        XCTAssertEqual(OverlayElementPart.availableParts(for: element), [.value])
    }

    private func firstMetricElementID(_ model: StudioModel) -> String? {
        model.layout.visibleElements.first { element in
            switch element.kind {
            case .speed, .route, .topProgress, .timeDate:
                return false
            default:
                return true
            }
        }?.id
    }
}
