import OverlayCore
import AVFoundation
import XCTest
@testable import OverlayTouch

@MainActor
final class TouchStudioModelTests: XCTestCase {
    private final class FakeSubscriptionEntitlement: SubscriptionEntitlementProviding {
        var hasActiveExportEntitlement: Bool

        init(hasActiveExportEntitlement: Bool) {
            self.hasActiveExportEntitlement = hasActiveExportEntitlement
        }
    }

    private final class FakeRuntimeGuard: TouchExportRuntimeGuarding {
        private(set) var endCount = 0

        func exportDidStart(onBackgroundExpiration: @escaping () -> Void) {}
        func exportDidEnd() { endCount += 1 }
    }

    private func makeModel(
        subscriptionEntitlement: (any SubscriptionEntitlementProviding)? = nil,
        runtimeGuard: TouchExportRuntimeGuarding = TouchExportRuntimeNoopGuard()
    ) -> TouchStudioModel {
        let defaults = UserDefaults(suiteName: "touch-tests-\(UUID().uuidString)")!
        return TouchStudioModel(
            layoutPresetStore: LayoutPresetStore(defaults: defaults),
            runtimeGuard: runtimeGuard,
            subscriptionEntitlement: subscriptionEntitlement
        )
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

    private func writeTinyVideo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("touch-video-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<2 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
            if let pixelBuffer {
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                    memset(base, 0x22, CVPixelBufferGetDataSize(pixelBuffer))
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 1))
            }
        }
        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func loadSampleVideo(into model: TouchStudioModel) async throws -> URL {
        let url = try writeTinyVideo()
        model.setVideo(url, isSecurityScoped: false)
        for _ in 0..<200 {
            if model.metadata != nil || model.videoLoadFailure != nil {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNil(model.videoLoadFailure?.detail)
        XCTAssertNotNil(model.metadata, "Video sample did not load in time")
        return url
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
        XCTAssertTrue(model.canAddElement(kind: .weather))
        XCTAssertFalse(model.canAddElement(kind: .power))
        XCTAssertFalse(model.canAddElement(kind: .heartRate))
    }

    func testExportWithoutSubscriptionRequestsPaywall() async throws {
        let entitlement = FakeSubscriptionEntitlement(hasActiveExportEntitlement: false)
        let model = makeModel(subscriptionEntitlement: entitlement)
        let videoURL = try await loadSampleVideo(into: model)
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try await loadSampleActivity(into: model)

        XCTAssertTrue(model.canExport)

        model.export()

        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(model.statusMessage.key, "status.exportNeedsSubscription")
        XCTAssertEqual(model.subscriptionPaywallRequestID, 1)
    }

    func testFailedSourceReplacementsKeepWorkingVideoAndActivity() async throws {
        let model = makeModel()
        let videoURL = try await loadSampleVideo(into: model)
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let originalVideoDuration = try XCTUnwrap(model.metadata).duration

        let activityURL = try writeSampleGPX()
        defer { try? FileManager.default.removeItem(at: activityURL) }
        model.setActivityFile(activityURL, isSecurityScoped: false)
        for _ in 0..<200 where model.series == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let originalActivityDuration = try XCTUnwrap(model.series).duration

        let invalidVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-touch-video-\(UUID().uuidString).mov")
        let invalidActivityURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-touch-activity-\(UUID().uuidString).gpx")
        try Data([0x00, 0x01, 0x02]).write(to: invalidVideoURL)
        try Data("not-gpx".utf8).write(to: invalidActivityURL)
        defer {
            try? FileManager.default.removeItem(at: invalidVideoURL)
            try? FileManager.default.removeItem(at: invalidActivityURL)
        }

        model.setVideo(invalidVideoURL, isSecurityScoped: false)
        for _ in 0..<200 where model.videoLoadFailure == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNotNil(model.videoLoadFailure)
        XCTAssertEqual(model.videoURL, videoURL)
        XCTAssertEqual(model.metadata?.duration, originalVideoDuration)

        model.setActivityFile(invalidActivityURL, isSecurityScoped: false)
        for _ in 0..<200 where model.activityLoadFailure == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNotNil(model.activityLoadFailure)
        XCTAssertEqual(model.activityURL, activityURL)
        XCTAssertEqual(model.series?.duration, originalActivityDuration)
    }

    func testTemporaryMovieCleanupPreservesEveryRetainedSceneFile() throws {
        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TouchTemporaryMovieStore.importedFilePrefix)\(UUID().uuidString).mov")
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TouchTemporaryMovieStore.importedFilePrefix)\(UUID().uuidString).mov")
        try Data([0x01]).write(to: first)
        try Data([0x02]).write(to: second)
        TouchTemporaryMovieStore.retain(first)
        TouchTemporaryMovieStore.retain(second)
        defer {
            TouchTemporaryMovieStore.release(first)
            TouchTemporaryMovieStore.release(second)
        }

        TouchTemporaryMovieStore.removeStaleFiles()

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        TouchTemporaryMovieStore.release(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testModelDeinitAlwaysEndsRuntimeGuard() {
        let guardSpy = FakeRuntimeGuard()
        var model: TouchStudioModel? = makeModel(runtimeGuard: guardSpy)
        XCTAssertNotNil(model)

        model = nil

        XCTAssertEqual(guardSpy.endCount, 1)
    }
}
