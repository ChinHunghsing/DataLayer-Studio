import OverlayCore
import XCTest
@testable import OverlayTouch

@MainActor
final class TouchStudioModelTests: XCTestCase {
    private func makeModel() -> TouchStudioModel {
        let defaults = UserDefaults(suiteName: "touch-tests-\(UUID().uuidString)")!
        return TouchStudioModel(layoutPresetStore: LayoutPresetStore(defaults: defaults))
    }

    private func writeSampleGPX() throws -> URL {
        var points = ""
        for index in 0..<30 {
            let seconds = String(format: "%02d", index)
            points += """
            <trkpt lat="35.65\(index)" lon="139.74\(index)"><ele>\(10 + index)</ele><time>2026-07-06T01:00:\(seconds)Z</time></trkpt>
            """
        }
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>test</name><trkseg>
        \(points)
        </trkseg></trk>
        </gpx>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("touch-test-\(UUID().uuidString)")
            .appendingPathExtension("gpx")
        try gpx.data(using: .utf8)!.write(to: url)
        return url
    }

    private func loadSampleActivity(into model: TouchStudioModel) async throws {
        let url = try writeSampleGPX()
        defer { try? FileManager.default.removeItem(at: url) }
        model.setActivityFile(url, isSecurityScoped: false)
        for _ in 0..<200 {
            if model.series != nil || model.activityLoadFailure != nil {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNil(model.activityLoadFailure?.detail)
        XCTAssertNotNil(model.series, "GPX sample did not load in time")
    }

    func testExportReadinessRequiresActivity() {
        let model = makeModel()
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.exportReadinessMessage?.key, "status.chooseFitFile")
    }

    func testActivityLoadResetsTrimToFullDuration() async throws {
        let model = makeModel()
        try await loadSampleActivity(into: model)

        XCTAssertEqual(model.effectiveExportTrimStart, 0, accuracy: 0.001)
        XCTAssertEqual(model.effectiveExportTrimEnd, model.series!.duration, accuracy: 0.001)
    }

    func testExportIsCompositedOnlyAndNeedsVideo() async throws {
        let model = makeModel()
        XCTAssertEqual(model.exportMode, .video)
        XCTAssertEqual(model.codec, .hevc)
        XCTAssertEqual(model.availableCodecs, [.hevc, .h264])

        try await loadSampleActivity(into: model)
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.exportReadinessMessage?.key, "status.chooseVideoForCompositedExport")
    }

    func testTimeSyncIsIdentityWithoutVideo() {
        let model = makeModel()
        model.syncMode = .offset
        model.offsetSeconds = 12
        XCTAssertEqual(model.timeSync, .identity)
    }

    func testElementAddDuplicateDeleteWithUndoRedo() {
        let model = makeModel()
        let initialCount = model.layout.elements.count

        model.addElement(kind: .power)
        XCTAssertEqual(model.layout.elements.count, initialCount + 1)
        let addedID = model.selectedElementID
        XCTAssertNotNil(addedID)
        XCTAssertTrue(model.canUndoLayout)

        model.duplicateSelectedElement()
        XCTAssertEqual(model.layout.elements.count, initialCount + 2)

        model.deleteSelectedElement()
        XCTAssertEqual(model.layout.elements.count, initialCount + 1)

        model.undoLayoutChange()
        XCTAssertEqual(model.layout.elements.count, initialCount + 2)
        XCTAssertTrue(model.canRedoLayout)

        model.redoLayoutChange()
        XCTAssertEqual(model.layout.elements.count, initialCount + 1)

        model.undoLayoutChange()
        model.undoLayoutChange()
        model.undoLayoutChange()
        XCTAssertEqual(model.layout.elements.count, initialCount)
        XCTAssertFalse(model.canUndoLayout)
    }

    func testNudgeClampsPosition() {
        let model = makeModel()
        guard let elementID = model.layout.elements.first?.id else {
            XCTFail("Default layout has no elements")
            return
        }
        model.selectElement(elementID)
        model.nudgeSelectedElement(deltaX: 100, deltaY: -100)
        let element = model.layout.elements.first { $0.id == elementID }!
        XCTAssertEqual(element.frame.x, TouchLayoutLimits.positionRange.upperBound, accuracy: 0.001)
        XCTAssertEqual(element.frame.y, TouchLayoutLimits.positionRange.lowerBound, accuracy: 0.001)
    }

    func testExportTrimSanitization() async throws {
        let model = makeModel()
        try await loadSampleActivity(into: model)
        let duration = model.series!.duration

        model.setExportTrimStart(-5)
        XCTAssertEqual(model.effectiveExportTrimStart, 0, accuracy: 0.001)

        model.setExportTrimEnd(duration + 100)
        XCTAssertEqual(model.effectiveExportTrimEnd, duration, accuracy: 0.001)

        model.setExportTrimStart(duration + 50)
        XCTAssertLessThan(model.effectiveExportTrimStart, duration)
        XCTAssertLessThanOrEqual(model.effectiveExportTrimStart, model.effectiveExportTrimEnd)
    }

    func testLayoutPresetSaveApplyDelete() {
        let model = makeModel()
        XCTAssertFalse(model.saveLayoutPreset(named: "   "))
        XCTAssertTrue(model.saveLayoutPreset(named: "Race"))
        XCTAssertEqual(model.layoutPresets.count, 1)

        let presetID = model.layoutPresets[0].id
        model.addElement(kind: .power)
        model.applyLayoutPreset(id: presetID)
        XCTAssertEqual(model.layout.elements.count, OverlayLayout.default.elements.count)

        model.setDefaultLayoutPreset(id: presetID)
        XCTAssertEqual(model.defaultLayoutPresetID, presetID)

        model.deleteLayoutPreset(id: presetID)
        XCTAssertTrue(model.layoutPresets.isEmpty)
        XCTAssertNil(model.defaultLayoutPresetID)
    }

    func testCanAddElementFollowsAvailableTelemetry() async throws {
        let model = makeModel()
        XCTAssertTrue(model.canAddElement(kind: .power))

        try await loadSampleActivity(into: model)
        XCTAssertTrue(model.canAddElement(kind: .route))
        XCTAssertTrue(model.canAddElement(kind: .timeDate))
        XCTAssertFalse(model.canAddElement(kind: .power))
        XCTAssertFalse(model.canAddElement(kind: .heartRate))
    }
}
