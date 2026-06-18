import XCTest
import OverlayCore
@testable import OverlayStudio

@MainActor
final class StudioModelTests: XCTestCase {
    func testLaunchOptionsParseVideoFITAndOffsetArguments() {
        let options = StudioLaunchOptions(arguments: [
            "Overlay Studio",
            "--video",
            "/tmp/source video.mp4",
            "--fit",
            "/tmp/activity.fit",
            "--offset",
            "120"
        ])

        XCTAssertEqual(options.videoURL?.path, "/tmp/source video.mp4")
        XCTAssertEqual(options.fitURL?.path, "/tmp/activity.fit")
        XCTAssertEqual(options.offsetSeconds, 120)
    }

    func testSanitizedOutputDimensionClampsAndRoundsToEvenPixels() {
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(1), 2)
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(2), 2)
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(3), 4)
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(1_919), 1_920)
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(16_383), 16_384)
        XCTAssertEqual(StudioModel.sanitizedOutputDimension(16_385), 16_384)
    }

    func testOutputDimensionSettersKeepGuiDimensionsExportable() {
        let model = StudioModel()

        model.setOutputWidth(1_919)
        model.setOutputHeight(1_079)

        XCTAssertEqual(model.outputWidth, 1_920)
        XCTAssertEqual(model.outputHeight, 1_080)
    }

    func testSanitizedOutputTimingAndBitrateClampToExportableRanges() {
        XCTAssertEqual(StudioModel.sanitizedOutputFrameRate(.nan), 1)
        XCTAssertEqual(StudioModel.sanitizedOutputFrameRate(0.5), 1)
        XCTAssertEqual(StudioModel.sanitizedOutputFrameRate(241), 240)

        XCTAssertEqual(StudioModel.sanitizedOutputDuration(.infinity), 0.1)
        XCTAssertEqual(StudioModel.sanitizedOutputDuration(0), 0.1)
        XCTAssertEqual(StudioModel.sanitizedOutputDuration(86_401), 86_400)

        XCTAssertEqual(StudioModel.sanitizedBitRateKbps(0), 1)
        XCTAssertEqual(StudioModel.sanitizedBitRateKbps(1_000_001), 1_000_000)
    }

    func testOutputTimingAndBitrateSettersKeepGuiValuesExportable() {
        let model = StudioModel()

        model.setOutputFPS(.infinity)
        model.setOutputDuration(0)
        model.setBitRateKbps(-20)

        XCTAssertEqual(model.outputFPS, 1)
        XCTAssertEqual(model.outputDuration, 0.1)
        XCTAssertEqual(model.bitRateKbps, 1)
    }

    func testGridDivisionSettersClampToPreviewBounds() {
        XCTAssertEqual(StudioModel.sanitizedGridDivision(1), 2)
        XCTAssertEqual(StudioModel.sanitizedGridDivision(65), 64)

        let model = StudioModel()
        model.setGridColumns(1)
        model.setGridRows(65)

        XCTAssertEqual(model.gridColumns, 2)
        XCTAssertEqual(model.gridRows, 64)
    }

    func testSourceFrameRatePresetOnlyAppearsWhenExportable() {
        let model = StudioModel()

        model.metadata = VideoMetadata(
            size: CGSize(width: 1920, height: 1080),
            duration: 10,
            framesPerSecond: 300
        )
        XCTAssertNil(model.sourceFrameRatePresetTitle)

        model.metadata = VideoMetadata(
            size: CGSize(width: 1920, height: 1080),
            duration: 10,
            framesPerSecond: 59.94
        )
        XCTAssertEqual(model.sourceFrameRatePresetTitle, "Source 59.940 fps")
    }

    func testRefreshPreviewClearsStaleWarningWithoutVideo() {
        let model = StudioModel()
        model.previewWarning = "Old preview warning"

        model.refreshPreview()

        XCTAssertNil(model.previewWarning)
        XCTAssertNil(model.backgroundImage)
        XCTAssertNil(model.overlayImage)
        XCTAssertNil(model.dragBaseOverlayImage)
        XCTAssertNil(model.dragOverlayImage)
    }

    func testRefreshOverlayOnlyClearsStaleWarningWithoutMissingInputs() {
        let model = StudioModel()
        model.previewWarning = "Old preview warning"

        model.refreshOverlayOnly()
        XCTAssertNil(model.previewWarning)

        model.videoURL = URL(fileURLWithPath: "/tmp/source.mov")
        model.previewWarning = "Old preview warning"
        model.refreshOverlayOnly()

        XCTAssertNil(model.previewWarning)
        XCTAssertNil(model.overlayImage)
    }

    func testUpdateElementCanSkipSelectionRepairForDragUpdates() {
        let model = StudioModel()
        let elementID = model.layout.elements[0].id
        model.selectedElementID = "missing"

        model.updateElement(elementID, refreshPreview: false) { element in
            element.frame.x += 0.01
        }
        XCTAssertEqual(model.selectedElementID, "missing")

        model.updateElement(elementID) { element in
            element.frame.x += 0.01
        }
        XCTAssertEqual(model.selectedElementID, model.layout.elements.first?.id)
    }

    func testSeekPreviewClampsTimeToOutputDuration() {
        let model = StudioModel()
        model.setOutputDuration(12)

        model.seekPreview(to: 20)
        XCTAssertEqual(model.previewTime, 12)

        model.seekPreview(to: -5)
        XCTAssertEqual(model.previewTime, 0)
    }
}
