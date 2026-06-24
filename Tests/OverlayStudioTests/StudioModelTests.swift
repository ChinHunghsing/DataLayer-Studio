import XCTest
import AppKit
import OverlayCore
@testable import OverlayStudio

@MainActor
final class StudioModelTests: XCTestCase {
    func testLaunchOptionsParseVideoFITAndOffsetArguments() {
        let options = StudioLaunchOptions(arguments: [
            "DataLayer Studio",
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

        XCTAssertEqual(StudioModel.sanitizedSourceDuration(.infinity), 0.1)
        XCTAssertEqual(StudioModel.sanitizedSourceDuration(0), 0.1)
        XCTAssertEqual(StudioModel.sanitizedSourceDuration(86_401), 86_400)

        XCTAssertEqual(StudioModel.sanitizedBitRateKbps(0), 1)
        XCTAssertEqual(StudioModel.sanitizedBitRateKbps(1_000_001), 1_000_000)
    }

    func testOutputTimingAndBitrateSettersKeepGuiValuesExportable() {
        let model = StudioModel()

        model.setOutputFPS(.infinity)
        model.setBitRateKbps(-20)

        XCTAssertEqual(model.outputFPS, 1)
        XCTAssertEqual(model.bitRateKbps, 1)
    }

    func testSourceVideoBitrateConvertsMetadataBitsPerSecondToKbps() {
        let metadata = VideoMetadata(
            size: CGSize(width: 1920, height: 1080),
            duration: 10,
            framesPerSecond: 30,
            bitRateBitsPerSecond: 12_345_678
        )

        XCTAssertEqual(StudioModel.sourceVideoBitRateKbps(from: metadata), 12_346)
    }

    func testAutoSuggestedOutputStillNeedsExplicitExportSelection() {
        let model = StudioModel()
        XCTAssertTrue(model.needsOutputSelectionBeforeExport)

        model.outputURL = URL(fileURLWithPath: "/tmp/manual.mov")
        XCTAssertFalse(model.needsOutputSelectionBeforeExport)

        model.outputURL = nil
        model.applySuggestedOutputURLIfNeeded(for: URL(fileURLWithPath: "/tmp/source.mov"))

        XCTAssertEqual(model.outputURL?.lastPathComponent, "source_overlay.mov")
        XCTAssertTrue(model.needsOutputSelectionBeforeExport)
    }

    func testFitOnlyModeCanExportWithFITDuration() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])

        XCTAssertTrue(model.canExport)
        XCTAssertTrue(model.canPreview)
        XCTAssertEqual(model.previewDuration, 5)
        XCTAssertNil(model.exportReadinessMessage)
    }

    func testFitOnlyModeIgnoresOffsetSync() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])
        model.syncMode = .offset
        model.offsetSeconds = 120

        XCTAssertEqual(model.timeSync.rawFitElapsed(forVideoTime: 3), 3)
    }

    func testWeatherRefreshReportsMissingKey() {
        let model = StudioModel()
        model.openWeatherAPIKey = ""
        model.fitURL = URL(fileURLWithPath: "/tmp/activity.fit")
        model.series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0)])

        model.refreshOpenWeatherForCurrentFIT()

        XCTAssertEqual(model.status, AppLocalizer.currentString("status.weatherKeyRequired"))
        XCTAssertEqual(model.weatherRefreshMessage, model.status)
    }

    func testExportReadinessReportsSourceDurationInsteadOfEditableDuration() {
        let model = StudioModel()
        model.videoURL = URL(fileURLWithPath: "/tmp/source.mov")
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])
        model.sourceDuration = .nan

        XCTAssertEqual(
            model.exportReadinessMessage,
            AppLocalizer.currentString("status.sourceDurationRange")
        )

        model.sourceDuration = 12

        XCTAssertNil(model.exportReadinessMessage)
    }

    func testStudioModelStringsFollowResolvedLanguage() {
        let model = StudioModel()
        model.setResolvedLanguage(.simplifiedChinese)

        XCTAssertEqual(model.exportReadinessMessage, "请选择 FIT 文件。")

        model.metadata = VideoMetadata(
            size: CGSize(width: 3840, height: 2160),
            duration: 10,
            framesPerSecond: 29.97
        )

        XCTAssertEqual(model.sourceResolutionPresetTitle, "源视频 3840×2160")
        XCTAssertEqual(model.sourceFrameRatePresetTitle, "源视频 29.970 fps")
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

    func testPreferenceStoreFallsBackToLegacyAppDomain() throws {
        let suiteName = "run.libo.datalayer-studio.preference-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyDomain = "\(suiteName).legacy"

        let legacyState = StudioPreferenceState(
            showGrid: true,
            gridColumns: 20,
            gridRows: 18,
            snapGaugeToGrid: true,
            distanceUnit: .meters
        )
        let data = try JSONEncoder().encode(legacyState)
        defaults.setPersistentDomain(
            [StudioPreferenceStore.storageKey: data],
            forName: legacyDomain
        )
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        let loaded = StudioPreferenceStore(defaults: defaults, appDomains: [legacyDomain]).load()

        XCTAssertEqual(loaded, legacyState)
    }

    func testPlaybackOverlayRefreshIsThrottledBelowPlayerTimeUpdates() {
        XCTAssertGreaterThan(StudioModel.playbackOverlayRefreshInterval, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThan(StudioModel.scrubOverlayRefreshInterval, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThanOrEqual(StudioModel.playerTimeObserverInterval, 0.10)
        XCTAssertLessThanOrEqual(StudioModel.playbackOverlayRefreshInterval, 0.25)
        XCTAssertLessThanOrEqual(StudioModel.scrubOverlayRefreshInterval, 1.0 / 55.0)
        XCTAssertGreaterThan(StudioModel.scrubInteractionHoldInterval, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThanOrEqual(StudioModel.scrubInteractionHoldInterval, 0.20)
    }

    func testDragOverlayRenderDelayStaysBelowPlaybackRefreshInterval() {
        XCTAssertGreaterThan(StudioModel.dragOverlayRenderDelay, 0)
        XCTAssertLessThanOrEqual(StudioModel.dragOverlayRenderDelay, 1.0 / 30.0)
        XCTAssertLessThan(StudioModel.dragOverlayRenderDelay, StudioModel.playbackOverlayRefreshInterval)
        XCTAssertGreaterThan(StudioModel.dragBaseOverlayRenderDelay, StudioModel.dragOverlayRenderDelay)
        XCTAssertLessThanOrEqual(StudioModel.dragBaseOverlayRenderDelay, 0.10)
    }

    func testPreviewGaugeDragStartsWithMinimalPointerTravel() {
        XCTAssertLessThanOrEqual(PreviewCanvasView.componentDragMinimumDistance, 1)
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
        XCTAssertEqual(
            model.sourceFrameRatePresetTitle,
            AppLocalizer.currentString("sidebar.sourceFrameRatePreset", "59.940")
        )
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

    func testSeekPreviewClampsTimeToSourceDuration() {
        let model = StudioModel()
        model.sourceDuration = 12

        model.seekPreview(to: 20)
        XCTAssertEqual(model.previewTime, 12)

        model.seekPreview(to: -5)
        XCTAssertEqual(model.previewTime, 0)
    }

    func testSeekPreviewClampsToFITDurationWithoutVideo() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 7, distanceMeters: 30)
        ])

        model.seekPreview(to: 20)

        XCTAssertEqual(model.previewTime, 7)
    }

    func testScrubPreviewWithoutVideoKeepsOverlayVisible() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 7, distanceMeters: 30)
        ])
        model.overlayImage = NSImage(size: CGSize(width: 8, height: 8))

        model.scrubPreview(to: 3)

        XCTAssertEqual(model.previewTime, 3)
        XCTAssertNotNil(model.overlayImage)
    }

    func testStepPreviewFrameUsesSourceFrameRateWhenAvailable() {
        let model = StudioModel()
        model.metadata = VideoMetadata(
            size: CGSize(width: 1920, height: 1080),
            duration: 10,
            framesPerSecond: 60
        )
        model.setOutputFPS(30)
        model.sourceDuration = 10
        model.seekPreview(to: 5)

        XCTAssertEqual(model.previewFrameRate, 60, accuracy: 0.0001)
        model.stepPreviewFrame(by: 1)
        XCTAssertEqual(model.previewTime, 5 + 1.0 / 60.0, accuracy: 0.0001)

        model.stepPreviewFrame(by: -2)
        XCTAssertEqual(model.previewTime, 5 - 1.0 / 60.0, accuracy: 0.0001)
    }

    func testStepPreviewFrameClampsToPreviewBounds() {
        let model = StudioModel()
        model.setOutputFPS(25)
        model.sourceDuration = 1

        model.seekPreview(to: 0)
        model.stepPreviewFrame(by: -1)
        XCTAssertEqual(model.previewTime, 0)

        model.seekPreview(to: 1)
        model.stepPreviewFrame(by: 1)
        XCTAssertEqual(model.previewTime, 1)
    }
}
