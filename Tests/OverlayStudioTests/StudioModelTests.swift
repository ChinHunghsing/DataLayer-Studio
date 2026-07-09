import XCTest
import AppKit
import AVFoundation
import CoreGraphics
import OverlayCore
@testable import OverlayStudio
@testable import OverlayStudioKit

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

    func testGaugeDragPreviewRenderSizeCapsLongestSide() {
        XCTAssertEqual(
            StudioModel.gaugeDragPreviewRenderSize(for: CGSize(width: 3_200, height: 1_800)),
            CGSize(width: 1_600, height: 900)
        )
        XCTAssertEqual(
            StudioModel.gaugeDragPreviewRenderSize(for: CGSize(width: 900, height: 3_200)),
            CGSize(width: 450, height: 1_600)
        )
        let smallSize = CGSize(width: 1_280, height: 720)
        XCTAssertEqual(StudioModel.gaugeDragPreviewRenderSize(for: smallSize), smallSize)
    }

    func testGaugeDragEndRestoresPreviewRenderSize() async throws {
        let model = StudioModel()
        model.setOutputWidth(2_000)
        model.setOutputHeight(1_000)
        model.updatePreviewOverlayRenderSize(CGSize(width: 2_000, height: 1_000))
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])

        model.beginGaugeDragInteraction()
        model.refreshOverlayOnly()
        try await waitForOverlayImage(in: model, timeout: 2)
        XCTAssertEqual(model.overlayImage?.width, 1_600)
        XCTAssertEqual(model.overlayImage?.height, 800)

        model.overlayImage = nil
        model.endGaugeDragInteraction()
        try await waitForOverlayImage(in: model, timeout: 2)
        XCTAssertEqual(model.overlayImage?.width, 2_000)
        XCTAssertEqual(model.overlayImage?.height, 1_000)
    }

    func testDeleteSelectedElementCanUndoAndRedo() {
        let model = StudioModel()
        let undoManager = UndoManager()
        model.undoManager = undoManager
        let originalLayout = model.layout
        let originalSelection = model.selectedElementID

        model.deleteSelectedElement()

        XCTAssertNotEqual(model.layout, originalLayout)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.layout, originalLayout)
        XCTAssertEqual(model.selectedElementID, originalSelection)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertNotEqual(model.layout, originalLayout)
        XCTAssertTrue(undoManager.canUndo)
    }

    func testGaugeDragRegistersSingleUndoStep() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        model.undoManager = undoManager
        let originalLayout = model.layout
        let elementID = try XCTUnwrap(model.selectedElementID)

        model.beginGaugeDragInteraction()
        model.updateElement(elementID, refreshPreview: false) { $0.frame.x = 0.5 }
        model.updateElement(elementID, refreshPreview: false) { $0.frame.x = 0.61 }
        model.updateElement(elementID, refreshPreview: false) { $0.frame.y = 0.35 }
        model.endGaugeDragInteraction()

        XCTAssertNotEqual(model.layout, originalLayout)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.layout, originalLayout)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testApplyLayoutPresetCanUndo() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        model.undoManager = undoManager
        var presetLayout = model.layout
        presetLayout.updateElement(id: try XCTUnwrap(model.selectedElementID)) { $0.frame.x = 0.9 }
        model.layoutPresets = [LayoutPreset(
            id: "preset-undo-test",
            name: "Undo Test",
            layout: presetLayout,
            createdAt: Date(),
            updatedAt: Date()
        )]
        let layoutBeforeApply = model.layout

        model.applyLayoutPreset(id: "preset-undo-test")

        XCTAssertNotEqual(model.layout, layoutBeforeApply)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.layout, layoutBeforeApply)
    }

    func testLayoutPresetsForDisplayPinsDefaultThenSortsByUpdatedAt() {
        let model = StudioModel()
        let old = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)
        let newest = Date(timeIntervalSince1970: 30)

        model.layoutPresets = [
            LayoutPreset(id: "old", name: "Old", layout: .default, createdAt: old, updatedAt: old),
            LayoutPreset(id: "newest", name: "Newest", layout: .default, createdAt: newest, updatedAt: newest),
            LayoutPreset(id: "default", name: "Default", layout: .default, createdAt: newer, updatedAt: newer)
        ]
        model.defaultLayoutPresetID = "default"

        XCTAssertEqual(model.layoutPresetsForDisplay.map(\.id), ["default", "newest", "old"])
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

    func testCanAddElementReflectsLoadedTelemetryData() {
        let model = StudioModel()
        XCTAssertTrue(model.canAddElement(kind: .heartRate))

        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: Date(timeIntervalSince1970: 1_000), latitude: 35, longitude: 139, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])

        XCTAssertTrue(model.canAddElement(kind: .pace))
        XCTAssertTrue(model.canAddElement(kind: .distance))
        XCTAssertTrue(model.canAddElement(kind: .route))
        XCTAssertTrue(model.canAddElement(kind: .weather))
        XCTAssertFalse(model.canAddElement(kind: .heartRate))
        XCTAssertFalse(model.canAddElement(kind: .strideLength))
        XCTAssertFalse(model.canAddElement(kind: .power))
        XCTAssertFalse(model.canAddElement(kind: .ascent))

        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, altitudeMeters: 10, heartRate: 120, stepLengthMeters: 1.2),
            TelemetrySample(elapsed: 1, altitudeMeters: 12)
        ])

        XCTAssertTrue(model.canAddElement(kind: .heartRate))
        XCTAssertTrue(model.canAddElement(kind: .strideLength))
        XCTAssertTrue(model.canAddElement(kind: .ascent))
        XCTAssertTrue(model.canAddElement(kind: .weather))
        XCTAssertFalse(model.canAddElement(kind: .route))
    }

    func testWeatherElementCanBeAddedBeforeAPIKeyAndWeatherData() {
        let model = StudioModel()
        model.openWeatherAPIKey = ""
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])

        XCTAssertTrue(model.canAddElement(kind: .weather))
        XCTAssertFalse(model.canAddElement(kind: .heartRate))
    }

    func testActivityTrimRebasesPreviewSampleData() {
        let model = StudioModel()
        let startDate = Date(timeIntervalSince1970: 1_000)
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: startDate, distanceMeters: 0, totalCalories: 10),
            TelemetrySample(elapsed: 10, date: startDate.addingTimeInterval(10), distanceMeters: 1_000, totalCalories: 60),
            TelemetrySample(elapsed: 20, date: startDate.addingTimeInterval(20), distanceMeters: 2_000, totalCalories: 110)
        ])
        model.activityTrim = ActivityTrim(startSeconds: 10, endSeconds: 20)

        let sample = model.displayTelemetrySample(forVideoTime: 15)

        XCTAssertEqual(sample.elapsed, 5, accuracy: 0.000_1)
        XCTAssertEqual(sample.distanceMeters ?? -1, 500, accuracy: 0.000_1)
        XCTAssertEqual(sample.totalCalories ?? -1, 25, accuracy: 0.000_1)
    }

    func testActivityTrimKeepsAbsoluteDateOnOriginalTimeline() throws {
        let model = StudioModel()
        let startDate = Date(timeIntervalSince1970: 2_000)
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: startDate, distanceMeters: 0),
            TelemetrySample(elapsed: 10, date: startDate.addingTimeInterval(10), distanceMeters: 1_000),
            TelemetrySample(elapsed: 20, date: startDate.addingTimeInterval(20), distanceMeters: 2_000)
        ])
        model.activityTrim = ActivityTrim(startSeconds: 10, endSeconds: 20)

        let date = try XCTUnwrap(model.absoluteActivityDate(forVideoTime: 15))

        XCTAssertEqual(date.timeIntervalSince1970, 2_015, accuracy: 0.000_1)
    }

    func testSportStartStatusUsesReadableDuration() {
        let model = StudioModel()
        model.setResolvedLanguage(.simplifiedChinese)
        model.previewTime = 133.369

        model.markSportStart()

        XCTAssertEqual(model.syncVideoSeconds, 133.369, accuracy: 0.000_1)
        XCTAssertEqual(model.status, "运动开始已设置在视频 2分13秒；运动时间从 00:00 开始。")
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

    func testNewVideoRefreshesSuggestedOutputNameInExistingDirectory() {
        let model = StudioModel()
        model.outputURL = URL(fileURLWithPath: "/tmp/exports/old.mov")

        model.applySuggestedOutputURLIfNeeded(
            for: URL(fileURLWithPath: "/tmp/videos/new-run.mp4"),
            replacingManualSelection: true
        )

        XCTAssertEqual(model.outputURL?.path, "/tmp/exports/new-run_overlay.mov")
        XCTAssertTrue(model.needsOutputSelectionBeforeExport)
    }

    func testExportModeRefreshesCodecAndSuggestedOutputName() {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/videos/new-run.mp4")
        model.videoURL = videoURL
        model.applySuggestedOutputURLIfNeeded(for: videoURL)

        XCTAssertEqual(model.outputURL?.lastPathComponent, "new-run_overlay.mov")
        XCTAssertEqual(model.codec, .hevcAlpha)

        model.exportMode = .video

        XCTAssertEqual(model.outputURL?.lastPathComponent, "new-run_with_overlay.mov")
        XCTAssertEqual(model.codec, .hevc)

        model.exportMode = .overlay

        XCTAssertEqual(model.outputURL?.lastPathComponent, "new-run_overlay.mov")
        XCTAssertEqual(model.codec, .hevcAlpha)
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

    func testActivityOnlyModeAllowsPreviewPlayback() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 30)
        ])

        XCTAssertNil(model.player)
        XCTAssertFalse(model.isPlaying)

        // 仅有运动数据、无视频时也应允许预览播放
        model.togglePlayback()
        XCTAssertTrue(model.isPlaying)

        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)
    }

    func testManualOutputURLDoesNotPreflightDestinationWritability() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])
        model.outputURL = URL(fileURLWithPath: "/tmp/datalayer-missing-output-directory/out.mov")

        XCTAssertTrue(model.canExport)
        XCTAssertNil(model.exportReadinessMessage)
    }

    func testExportTrimRangeDefaultsToFullActivityAndClamps() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 40)
        ])

        XCTAssertEqual(model.effectiveExportTrimStart, 0)
        XCTAssertEqual(model.effectiveExportTrimEnd, 10)
        XCTAssertEqual(model.effectiveExportTrimDuration, 10)
        XCTAssertTrue(model.canExport)

        model.setExportTrimStart(2.5)
        model.setExportTrimEnd(7.25)

        XCTAssertEqual(model.effectiveExportTrimStart, 2.5, accuracy: 0.000_1)
        XCTAssertEqual(model.effectiveExportTrimEnd, 7.25, accuracy: 0.000_1)
        XCTAssertEqual(model.effectiveExportTrimDuration, 4.75, accuracy: 0.000_1)

        model.setExportTrimEnd(2.52)

        XCTAssertEqual(model.effectiveExportTrimEnd, 2.6, accuracy: 0.000_1)

        model.resetExportTrimRange()

        XCTAssertEqual(model.effectiveExportTrimStart, 0)
        XCTAssertEqual(model.effectiveExportTrimEnd, 10)
    }

    func testFitOnlyModeCannotExportCompositedVideo() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])

        model.exportMode = .video

        XCTAssertFalse(model.canExport)
        XCTAssertEqual(
            model.exportReadinessMessage,
            AppLocalizer.currentString("status.chooseVideoForCompositedExport")
        )
    }

    func testModeSpecificExportReadinessKeepsOverlayAvailableWithoutVideo() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])
        model.exportMode = .video

        XCTAssertFalse(model.canExport)
        XCTAssertTrue(model.canExport(as: .overlay))
        XCTAssertNil(model.exportReadinessMessage(for: .overlay))
        XCTAssertFalse(model.canExport(as: .video))
        XCTAssertEqual(
            model.exportReadinessMessage(for: .video),
            AppLocalizer.currentString("status.chooseVideoForCompositedExport")
        )
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

    func testLegacySyncModesCollapseToEquivalentMatchPoint() {
        let model = StudioModel()

        model.syncMode = .offset
        model.offsetSeconds = 120
        model.useMatchPointSyncMode()
        XCTAssertEqual(model.syncMode, .syncPoint)
        XCTAssertEqual(model.syncVideoSeconds, 120)
        XCTAssertEqual(model.syncFITSeconds, 0)

        model.syncMode = .offset
        model.offsetSeconds = -45
        model.useMatchPointSyncMode()
        XCTAssertEqual(model.syncVideoSeconds, 0)
        XCTAssertEqual(model.syncFITSeconds, 45)

        model.syncMode = .fitStart
        model.fitStartSeconds = 30
        model.useMatchPointSyncMode()
        XCTAssertEqual(model.syncVideoSeconds, 0)
        XCTAssertEqual(model.syncFITSeconds, 30)
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

        XCTAssertEqual(model.exportReadinessMessage, "请选择 FIT 或 GPX 文件。")

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

    func testPreviewTimingConstantsStayResponsive() {
        XCTAssertGreaterThan(StudioModel.playbackOverlayRefreshInterval, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThanOrEqual(StudioModel.playerTimeObserverInterval, 0.10)
        XCTAssertLessThanOrEqual(StudioModel.playbackOverlayRefreshInterval, 0.25)
        XCTAssertGreaterThan(StudioModel.scrubInteractionHoldInterval, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThanOrEqual(StudioModel.scrubInteractionHoldInterval, 0.20)
        XCTAssertGreaterThan(StudioModel.previewResizeRefreshDelay, StudioModel.playerTimeObserverInterval)
        XCTAssertLessThanOrEqual(StudioModel.previewResizeRefreshDelay, 0.20)
    }

    func testPreviewLiveResizeDefersOverlayRefreshUntilResizeEnds() async throws {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 20)
        ])

        model.setPreviewLiveResizing(true)
        model.updatePreviewOverlayRenderSize(CGSize(width: 640, height: 360))
        model.updatePreviewOverlayRenderSize(CGSize(width: 1_280, height: 720))
        try await Task.sleep(nanoseconds: UInt64((StudioModel.previewResizeRefreshDelay + 0.08) * 1_000_000_000))

        XCTAssertNil(model.overlayImage)

        model.setPreviewLiveResizing(false)
        try await waitForOverlayImage(in: model)

        XCTAssertNotNil(model.overlayImage)
        XCTAssertEqual(model.overlayImage?.width, 1_280)
        XCTAssertEqual(model.overlayImage?.height, 720)
    }

    func testPreviewCanvasStateIgnoresUnrelatedDebugLogChanges() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)])
        let initialState = PreviewCanvasState(model: model)

        model.debugLogEntries.append(DebugLogEntry(date: Date(), category: .preview, message: "noise"))

        XCTAssertEqual(PreviewCanvasState(model: model), initialState)
    }

    func testPreviewControlsStateIgnoresUnrelatedDebugLogChanges() {
        let model = StudioModel()
        model.series = TelemetrySeries(samples: [TelemetrySample(elapsed: 0, distanceMeters: 0)])
        let initialState = PreviewControlsState(model: model)

        model.debugLogEntries.append(DebugLogEntry(date: Date(), category: .preview, message: "noise"))

        XCTAssertEqual(PreviewControlsState(model: model), initialState)
    }

    func testPreviewGaugeDragStartsWithMinimalPointerTravel() {
        XCTAssertLessThanOrEqual(PreviewCanvasView.componentDragMinimumDistance, 1)
    }

    func testPreviewTimelineKeepsScrubInputSensitive() {
        XCTAssertLessThanOrEqual(PreviewTimelineSlider.valueChangeEpsilon, 0.001)
    }

    @MainActor
    func testScrubPreviewWithPlayerRefreshesOverlay() async throws {
        let model = StudioModel()
        model.player = AVPlayer()
        model.videoURL = URL(fileURLWithPath: "/tmp/source.mov")
        model.setOutputWidth(320)
        model.setOutputHeight(180)
        model.series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 3, distanceMeters: 12)
        ])

        model.scrubPreview(to: 3)

        try await waitForOverlayImage(in: model)
        XCTAssertEqual(model.previewTime, 3)
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

    func testPreviewTimeClampsToExportTrimRange() {
        let model = StudioModel()
        model.sourceDuration = 12
        model.setExportTrimStart(4)
        model.setExportTrimEnd(8)

        model.seekPreview(to: 2)
        XCTAssertEqual(model.previewTime, 4)

        model.seekPreview(to: 10)
        XCTAssertEqual(model.previewTime, 8)

        model.seekPreview(to: 6)
        model.stepPreviewFrame(by: 1_000)
        XCTAssertEqual(model.previewTime, 8)
    }

    func testChangingExportTrimRangeMovesPreviewIntoRange() {
        let model = StudioModel()
        model.sourceDuration = 12
        model.seekPreview(to: 2)

        model.setExportTrimStart(4)
        XCTAssertEqual(model.previewTime, 4)

        model.seekPreview(to: 10)
        model.setExportTrimEnd(8)
        XCTAssertEqual(model.previewTime, 8)
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
        model.overlayImage = makeBlankCGImage(width: 8, height: 8)

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

    private func waitForOverlayImage(in model: StudioModel, timeout: TimeInterval = 1) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.overlayImage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeBlankCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testExportProgressEstimatesRemainingTimeFromRate() {
        let model = StudioModel()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        model.updateExportProgress(0, at: start)
        XCTAssertNil(model.exportETASeconds)

        model.updateExportProgress(0.1, at: start.addingTimeInterval(2))
        // 0.1 progress in 2 s -> rate 0.05/s -> remaining 0.9 / 0.05 = 18 s
        XCTAssertEqual(model.exportETASeconds ?? 0, 18, accuracy: 0.01)

        model.updateExportProgress(1, at: start.addingTimeInterval(20))
        XCTAssertEqual(model.exportETASeconds ?? 0, 18, accuracy: 0.01)
    }

    func testExportProgressSkipsETAWithoutEnoughSignal() {
        let model = StudioModel()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)

        model.updateExportProgress(0.01, at: start)
        model.updateExportProgress(0.015, at: start.addingTimeInterval(2))
        XCTAssertNil(model.exportETASeconds)

        model.updateExportProgress(0.5, at: start.addingTimeInterval(2.5))
        XCTAssertNotNil(model.exportETASeconds)
    }

    func testNudgeElementMovesFrameAndSupportsUndo() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        model.undoManager = undoManager
        let elementID = try XCTUnwrap(model.selectedElementID)
        let originalLayout = model.layout
        let originalX = try XCTUnwrap(model.layout.elements.first { $0.id == elementID }).frame.x

        model.nudgeElement(elementID, deltaX: 0.01, deltaY: 0)

        let movedX = try XCTUnwrap(model.layout.elements.first { $0.id == elementID }).frame.x
        XCTAssertEqual(movedX, originalX + 0.01, accuracy: 0.000_001)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.layout, originalLayout)
    }

    func testStatusRelocalizesWhenLanguageChanges() {
        let model = StudioModel()

        model.setResolvedLanguage(.english)
        XCTAssertEqual(model.status, AppLocalizer.string("status.chooseVideoAndFit", language: .english))

        model.setResolvedLanguage(.simplifiedChinese)
        XCTAssertEqual(model.status, AppLocalizer.string("status.chooseVideoAndFit", language: .simplifiedChinese))
    }

    func testFitLoadFailureSurfacesInlineErrorWithRetrySource() async throws {
        let model = StudioModel()
        let missingURL = URL(fileURLWithPath: "/nonexistent/datalayer-studio-tests/missing.fit")

        model.setFIT(missingURL)
        try await waitUntil { model.fitLoadFailure != nil }

        let failure = try XCTUnwrap(model.fitLoadFailure)
        XCTAssertEqual(failure.url, missingURL)
        XCTAssertEqual(failure.messageKey, "status.fitError")
        XCTAssertFalse(failure.detail.isEmpty)

        model.setFIT(missingURL)
        XCTAssertNil(model.fitLoadFailure)
    }
}
