import XCTest
import OverlayCore
@testable import OverlayStudio

final class CanvasArrangementTests: XCTestCase {
    func testAlignmentRequiresAtLeastTwoRects() {
        let offsets = CanvasArrangement.alignmentOffsets(
            rects: [CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)],
            alignment: .left
        )
        XCTAssertEqual(offsets, [.zero])
    }

    func testAlignLeftUsesLeftmostEdge() {
        let rects = [
            CGRect(x: 0.3, y: 0.1, width: 0.1, height: 0.1),
            CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.1),
            CGRect(x: 0.5, y: 0.7, width: 0.1, height: 0.1)
        ]
        let offsets = CanvasArrangement.alignmentOffsets(rects: rects, alignment: .left)
        XCTAssertEqual(offsets[0].dx, -0.2, accuracy: 1e-9)
        XCTAssertEqual(offsets[1].dx, 0, accuracy: 1e-9)
        XCTAssertEqual(offsets[2].dx, -0.4, accuracy: 1e-9)
        XCTAssertTrue(offsets.allSatisfy { $0.dy == 0 })
    }

    func testAlignRightUsesRightmostEdge() {
        let rects = [
            CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
            CGRect(x: 0.5, y: 0.4, width: 0.2, height: 0.1)
        ]
        let offsets = CanvasArrangement.alignmentOffsets(rects: rects, alignment: .right)
        XCTAssertEqual(offsets[0].dx, 0.5, accuracy: 1e-9)
        XCTAssertEqual(offsets[1].dx, 0, accuracy: 1e-9)
    }

    func testAlignHorizontalCenterUsesSelectionBoundsCenter() {
        let rects = [
            CGRect(x: 0.0, y: 0.1, width: 0.2, height: 0.1),
            CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.1)
        ]
        // Selection bounds span 0.0...0.8, center 0.4.
        let offsets = CanvasArrangement.alignmentOffsets(rects: rects, alignment: .horizontalCenter)
        XCTAssertEqual(offsets[0].dx, 0.3, accuracy: 1e-9)
        XCTAssertEqual(offsets[1].dx, -0.3, accuracy: 1e-9)
    }

    func testAlignTopAndBottomOperateOnVerticalAxis() {
        let rects = [
            CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.1),
            CGRect(x: 0.4, y: 0.5, width: 0.1, height: 0.2)
        ]
        let top = CanvasArrangement.alignmentOffsets(rects: rects, alignment: .top)
        XCTAssertEqual(top[0].dy, 0, accuracy: 1e-9)
        XCTAssertEqual(top[1].dy, -0.3, accuracy: 1e-9)

        let bottom = CanvasArrangement.alignmentOffsets(rects: rects, alignment: .bottom)
        XCTAssertEqual(bottom[0].dy, 0.4, accuracy: 1e-9)
        XCTAssertEqual(bottom[1].dy, 0, accuracy: 1e-9)
    }

    func testDistributionRequiresAtLeastThreeRects() {
        let rects = [
            CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
            CGRect(x: 0.5, y: 0.1, width: 0.1, height: 0.1)
        ]
        let offsets = CanvasArrangement.distributionOffsets(rects: rects, distribution: .horizontal)
        XCTAssertEqual(offsets, [.zero, .zero])
    }

    func testHorizontalDistributionEqualizesGapsAndKeepsEnds() {
        let rects = [
            CGRect(x: 0.0, y: 0.1, width: 0.1, height: 0.1),
            CGRect(x: 0.12, y: 0.4, width: 0.2, height: 0.1),
            CGRect(x: 0.7, y: 0.7, width: 0.1, height: 0.1)
        ]
        let offsets = CanvasArrangement.distributionOffsets(rects: rects, distribution: .horizontal)
        XCTAssertEqual(offsets[0], .zero)
        XCTAssertEqual(offsets[2], .zero)

        let moved = CGRect(
            x: rects[1].minX + offsets[1].dx,
            y: rects[1].minY,
            width: rects[1].width,
            height: rects[1].height
        )
        let gap1 = moved.minX - rects[0].maxX
        let gap2 = rects[2].minX - moved.maxX
        XCTAssertEqual(gap1, gap2, accuracy: 1e-9)
        XCTAssertEqual(offsets[1].dy, 0)
    }

    func testVerticalDistributionSortsByPositionNotInputOrder() {
        // Input order intentionally shuffled relative to vertical position.
        let rects = [
            CGRect(x: 0.1, y: 0.8, width: 0.1, height: 0.1),
            CGRect(x: 0.4, y: 0.0, width: 0.1, height: 0.1),
            CGRect(x: 0.7, y: 0.15, width: 0.1, height: 0.1)
        ]
        let offsets = CanvasArrangement.distributionOffsets(rects: rects, distribution: .vertical)
        // Outermost rects (indexes 1 and 0) stay put; the middle one (index 2) moves.
        XCTAssertEqual(offsets[0], .zero)
        XCTAssertEqual(offsets[1], .zero)

        let moved = rects[2].offsetBy(dx: 0, dy: offsets[2].dy)
        let gap1 = moved.minY - rects[1].maxY
        let gap2 = rects[0].minY - moved.maxY
        XCTAssertEqual(gap1, gap2, accuracy: 1e-9)
    }
}

@MainActor
final class CanvasSelectionTests: XCTestCase {
    private func makeModelWithThreeElements() -> (StudioModel, [String]) {
        let model = StudioModel()
        let ids = model.layout.visibleElements.prefix(3).map(\.id)
        return (model, Array(ids))
    }

    func testToggleElementInSelectionAddsAndRemoves() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.selectElement(id: ids[0])
        model.toggleElementInSelection(id: ids[1])
        XCTAssertEqual(model.selectedElementIDs, Set(ids.prefix(2)))
        XCTAssertEqual(model.selectedElementID, ids[1])

        model.toggleElementInSelection(id: ids[1])
        XCTAssertEqual(model.selectedElementIDs, [ids[0]])
        XCTAssertEqual(model.selectedElementID, ids[0])
    }

    func testSingleSelectCollapsesMultiSelection() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.selectElement(id: ids[0])
        model.toggleElementInSelection(id: ids[1])
        model.selectElement(id: ids[0])
        XCTAssertEqual(model.selectedElementIDs, [ids[0]])
    }

    func testSetElementSelectionValidatesIDsAndKeepsPrimary() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.selectElement(id: ids[0])
        model.setElementSelection(Set(ids.prefix(2)).union(["missing-element"]))
        XCTAssertEqual(model.selectedElementIDs, Set(ids.prefix(2)))
        XCTAssertEqual(model.selectedElementID, ids[0])

        model.setElementSelection([])
        XCTAssertTrue(model.selectedElementIDs.isEmpty)
        XCTAssertNil(model.selectedElementID)
    }

    func testDeleteSelectedElementRemovesWholeSelection() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.selectElement(id: ids[0])
        model.toggleElementInSelection(id: ids[1])
        model.deleteSelectedElement()

        XCTAssertFalse(model.layout.elements.contains { $0.id == ids[0] })
        XCTAssertFalse(model.layout.elements.contains { $0.id == ids[1] })
    }

    func testAlignLeftMovesSelectionToCommonLeftEdge() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.updateElement(ids[0]) { $0.frame.x = 0.1; $0.frame.y = 0.1 }
        model.updateElement(ids[1]) { $0.frame.x = 0.4; $0.frame.y = 0.5 }
        model.setElementSelection(Set(ids.prefix(2)))
        XCTAssertTrue(model.canAlignSelectedElements)

        model.alignSelectedElements(.left)

        let geometry = CanvasElementGeometry(model: model)
        let alignedWidth = geometry.alignedMetricOutputWidth(for: model.layout.visibleElements)
        let rects = ids.prefix(2).compactMap { id in
            model.layout.elements.first { $0.id == id }.map {
                geometry.unitRect(element: $0, alignedMetricWidth: alignedWidth)
            }
        }
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, rects[1].minX, accuracy: 1e-9)
    }

    func testDistributeNeedsAtLeastThreeSelected() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 3 else { return XCTFail("default layout needs at least 3 elements") }

        model.setElementSelection(Set(ids.prefix(2)))
        XCTAssertFalse(model.canDistributeSelectedElements)

        model.setElementSelection(Set(ids.prefix(3)))
        XCTAssertTrue(model.canDistributeSelectedElements)
    }

    func testPasteStyleKeepsContentDataAndPosition() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2 else { return XCTFail("default layout needs at least 2 elements") }

        model.updateElement(ids[0]) { element in
            element.frame.style.textScale = 1.7
            element.customization.valueFont = .futuraCondensedExtraBold
            element.customization.labelOverride = "SOURCE"
            element.customization.valuePrecision = 2
        }
        model.updateElement(ids[1]) { element in
            element.frame.x = 0.62
            element.customization.labelOverride = "TARGET"
            element.customization.valuePrecision = 1
        }

        model.copyElementStyle(id: ids[0])
        model.selectElement(id: ids[1])
        XCTAssertTrue(model.canPasteElementStyle)
        model.pasteCopiedElementStyle()

        let target = model.layout.elements.first { $0.id == ids[1] }
        XCTAssertEqual(target?.frame.style.textScale, 1.7)
        XCTAssertEqual(target?.customization.valueFont, .futuraCondensedExtraBold)
        XCTAssertEqual(target?.customization.labelOverride, "TARGET")
        XCTAssertEqual(target?.customization.valuePrecision, 1)
        XCTAssertEqual(target?.frame.x, 0.62)
    }

    func testBringSelectionToFrontAndBackReordersElements() {
        let (model, ids) = makeModelWithThreeElements()
        guard ids.count >= 2, model.layout.elements.count >= 3 else {
            return XCTFail("default layout needs at least 3 elements")
        }

        model.selectElement(id: ids[0])
        model.bringSelectedElementToFront()
        XCTAssertEqual(model.layout.elements.last?.id, ids[0])

        model.sendSelectedElementToBack()
        XCTAssertEqual(model.layout.elements.first?.id, ids[0])
    }
}
