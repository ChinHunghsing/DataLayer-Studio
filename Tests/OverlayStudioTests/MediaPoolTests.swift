import XCTest
import AVFoundation
import CoreGraphics
import OverlayCore
@testable import OverlayStudio

@MainActor
final class MediaPoolTests: XCTestCase {
    private func videoMetadata(width: CGFloat, height: CGFloat, duration: TimeInterval, fps: Double) -> VideoMetadata {
        VideoMetadata(
            size: CGSize(width: width, height: height),
            duration: duration,
            framesPerSecond: fps,
            bitRateBitsPerSecond: 0
        )
    }

    func testUpsertVideoDeduplicatesByPathAndRefreshes() {
        let model = StudioModel()
        let url = URL(fileURLWithPath: "/tmp/a.mov")

        model.upsertVideoAsset(url: url, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: url, metadata: videoMetadata(width: 1280, height: 720, duration: 120, fps: 25))

        XCTAssertEqual(model.videoAssets.count, 1)
        XCTAssertEqual(model.videoAssets[0].width, 1280)
        XCTAssertEqual(model.videoAssets[0].height, 720)
        XCTAssertEqual(model.videoAssets[0].duration, 120)
    }

    func testMultipleVideosCoexistInPool() {
        let model = StudioModel()
        model.upsertVideoAsset(url: URL(fileURLWithPath: "/tmp/a.mov"), metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: URL(fileURLWithPath: "/tmp/b.mov"), metadata: videoMetadata(width: 3840, height: 2160, duration: 50, fps: 60))
        XCTAssertEqual(model.videoAssets.map(\.id), ["/tmp/a.mov", "/tmp/b.mov"])
    }

    func testActiveVideoDerivedFromLoadedURL() {
        let model = StudioModel()
        let url = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: url, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        XCTAssertNil(model.activeVideoAssetID)

        model.videoURL = url
        XCTAssertEqual(model.activeVideoAssetID, "/tmp/a.mov")
    }

    func testCannotRemoveActiveVideoButCanRemoveOthers() {
        let model = StudioModel()
        let active = URL(fileURLWithPath: "/tmp/a.mov")
        let other = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: active, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: other, metadata: videoMetadata(width: 1280, height: 720, duration: 80, fps: 30))
        model.videoURL = active

        model.removeVideoAsset(id: "/tmp/a.mov") // active -> ignored
        XCTAssertEqual(model.videoAssets.count, 2)

        model.removeVideoAsset(id: "/tmp/b.mov") // non-active -> removed
        XCTAssertEqual(model.videoAssets.map(\.id), ["/tmp/a.mov"])
    }

    func testCurrentTimelineProjectReflectsActiveSources() {
        let model = StudioModel()
        XCTAssertTrue(model.currentTimelineProject.tracks.isEmpty)

        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL

        let fitURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: fitURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 90, distanceMeters: 300)
        ]))
        model.fitURL = fitURL

        let project = model.currentTimelineProject
        XCTAssertEqual(project.tracks.count, 2)
        XCTAssertEqual(project.tracks[0].kind, .video)   // base
        XCTAssertEqual(project.tracks[1].kind, .overlay) // on top
        XCTAssertEqual(project.tracks[0].clips.first?.duration, 120)
    }

    func testStoredTimelineUpdatesWhenSyncAndLayoutChange() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL

        let fitURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: fitURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 90, distanceMeters: 300)
        ]))
        model.fitURL = fitURL

        model.setActivitySyncZeroVideoTime(12)
        let overlayClip = try XCTUnwrap(model.timeline.tracks.last?.clips.first)
        XCTAssertEqual(overlayClip.timelineStart, 12, accuracy: 1e-9)

        model.setOutputWidth(1280)
        XCTAssertEqual(model.timeline.outputWidth, 1280)

        let newLayout = OverlayLayout(elements: [])
        model.layout = newLayout
        XCTAssertEqual(model.timeline.tracks.last?.clips.first?.layout, newLayout.sanitized)
    }

    func testAddingPooledActivityCreatesSeparateOverlaySeriesForExport() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL

        let firstURL = URL(fileURLWithPath: "/tmp/a.fit")
        let firstSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ])
        model.upsertActivityAsset(url: firstURL, series: firstSeries)
        model.fitURL = firstURL

        let secondURL = URL(fileURLWithPath: "/tmp/b.fit")
        let secondSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ])
        model.upsertActivityAsset(url: secondURL, series: secondSeries)
        model.previewTime = 12

        model.addActivityAssetToTimeline(id: secondURL.path)

        let overlayClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
        XCTAssertEqual(overlayClips.count, 2)
        XCTAssertEqual(overlayClips.last?.assetID, secondURL.path)
        XCTAssertEqual(overlayClips.last?.timelineStart ?? -1, 12, accuracy: 1e-9)

        let exportSeries = model.timelineTelemetrySeriesForExport(project: model.currentTimelineProject)
        XCTAssertEqual(exportSeries[firstURL.path]?.duration, firstSeries.duration)
        XCTAssertEqual(exportSeries[secondURL.path]?.duration, secondSeries.duration)

        model.setOutputWidth(1280)
        let overlaysAfterOutputChange = model.currentTimelineProject.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
        XCTAssertEqual(overlaysAfterOutputChange.count, 2)
        XCTAssertEqual(model.currentTimelineProject.outputWidth, 1280)
    }

    func testAddingPooledActivityCanAppendToTargetOverlayTrack() throws {
        let model = StudioModel()
        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = activeURL

        let firstPooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: firstPooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.addActivityAssetToTimeline(id: firstPooledURL.path)

        let targetTrack = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .first { $0.clips.contains { $0.assetID == firstPooledURL.path } }
        )

        let secondPooledURL = URL(fileURLWithPath: "/tmp/c.fit")
        model.upsertActivityAsset(url: secondPooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 30, distanceMeters: 120)
        ]))
        model.addActivityAssetToTimeline(
            id: secondPooledURL.path,
            targetTrackID: targetTrack.id,
            timelineStart: 33
        )

        let overlayTracks = model.currentTimelineProject.tracks.filter { $0.kind == .overlay }
        XCTAssertEqual(overlayTracks.count, 2)

        let updatedTrack = try XCTUnwrap(overlayTracks.first { $0.id == targetTrack.id })
        XCTAssertEqual(updatedTrack.clips.count, 2)
        XCTAssertEqual(updatedTrack.clips.last?.assetID, secondPooledURL.path)
        XCTAssertEqual(updatedTrack.clips.last?.timelineStart ?? -1, 33, accuracy: 1e-9)
    }

    func testTimelineOverlayDragWritesMatchPointSync() {
        let model = StudioModel()
        model.videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.fitURL = URL(fileURLWithPath: "/tmp/a.fit")

        // Drag so activity 0 lands at video 30s.
        model.setActivitySyncZeroVideoTime(30)
        XCTAssertEqual(model.syncVideoSeconds, 30, accuracy: 1e-9)
        XCTAssertEqual(model.syncFITSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, 30, accuracy: 1e-9)

        // Drag the other way (activity begins before the video starts).
        model.setActivitySyncZeroVideoTime(-12)
        XCTAssertEqual(model.syncVideoSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(model.syncFITSeconds, 12, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, -12, accuracy: 1e-9)
    }

    func testMovingPooledActivityClipUpdatesOnlyThatTimelineClip() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL

        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = activeURL
        model.setActivitySyncZeroVideoTime(10)

        let pooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: pooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.previewTime = 20
        model.addActivityAssetToTimeline(id: pooledURL.path)

        let customClip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.assetID == pooledURL.path }
        )

        model.moveTimelineClip(id: customClip.id, toTimelineStart: 32)

        let movedClip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.id == customClip.id }
        )
        XCTAssertEqual(movedClip.timelineStart, 32, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, 10, accuracy: 1e-9)
    }

    func testAddingPooledVideoAppendsToVideoTrack() throws {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL

        model.addVideoAssetToTimeline(id: secondURL.path)

        let videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.count, 2)
        XCTAssertEqual(videoClips[0].assetID, firstURL.path)
        XCTAssertEqual(videoClips[1].assetID, secondURL.path)
        XCTAssertEqual(videoClips[1].timelineStart, 100, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].duration, 40, accuracy: 1e-9)
    }

    func testCustomTimelinePreviewAndExportTrimUseTimelineDuration() {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL

        model.addVideoAssetToTimeline(id: secondURL.path)

        XCTAssertEqual(model.previewDuration, 140, accuracy: 1e-9)
        XCTAssertEqual(model.exportTrimSourceDuration, 140, accuracy: 1e-9)
    }

    func testTrimmingPooledTimelineClipUpdatesClipGeometry() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL

        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = activeURL

        let pooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: pooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.previewTime = 20
        model.addActivityAssetToTimeline(id: pooledURL.path)

        let clip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.assetID == pooledURL.path }
        )

        model.trimTimelineClipStart(id: clip.id, toTimelineTime: 25)
        model.trimTimelineClipEnd(id: clip.id, toTimelineTime: 60)

        let trimmed = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.id == clip.id }
        )
        XCTAssertEqual(trimmed.timelineStart, 25, accuracy: 1e-9)
        XCTAssertEqual(trimmed.sourceIn, 5, accuracy: 1e-9)
        XCTAssertEqual(trimmed.duration, 35, accuracy: 1e-9)
    }

    func testSelectingAndEditingPooledTimelineClipUpdatesClipSettings() throws {
        let model = StudioModel()
        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 60, distanceMeters: 300)
        ]))
        model.fitURL = activeURL

        let pooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: pooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.previewTime = 12
        model.addActivityAssetToTimeline(id: pooledURL.path)

        let clip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.assetID == pooledURL.path }
        )

        model.selectTimelineClip(id: clip.id)
        XCTAssertEqual(model.selectedTimelineClipID, clip.id)
        XCTAssertNil(model.selectedElement)

        model.setTimelineClipTiming(id: clip.id, timelineStart: 18, sourceIn: 4, duration: 20)
        model.setTimelineClipDistanceUnit(id: clip.id, .meters)

        var customLayout = model.layout
        customLayout.elements[0].frame.x = 0.42
        model.setTimelineClipLayout(id: clip.id, customLayout)

        let edited = try XCTUnwrap(model.selectedTimelineClip)
        XCTAssertEqual(edited.timelineStart, 18, accuracy: 1e-9)
        XCTAssertEqual(edited.sourceIn, 4, accuracy: 1e-9)
        XCTAssertEqual(edited.duration, 20, accuracy: 1e-9)
        XCTAssertEqual(edited.distanceUnit, .meters)
        XCTAssertEqual(try XCTUnwrap(edited.layout?.elements[0].frame.x), 0.42, accuracy: 1e-9)

        let elementID = try XCTUnwrap(model.layout.elements.first?.id)
        model.selectElement(id: elementID)
        XCTAssertNil(model.selectedTimelineClipID)
        XCTAssertEqual(model.selectedElement?.id, elementID)
    }

    func testTimelineOverlayDragIgnoredWithoutBothSources() {
        let model = StudioModel()
        model.videoURL = URL(fileURLWithPath: "/tmp/a.mov") // no activity
        model.setActivitySyncZeroVideoTime(30)
        XCTAssertEqual(model.syncVideoSeconds, 0) // unchanged
    }

    func testUpsertActivityAndActiveDerivation() {
        let model = StudioModel()
        let url = URL(fileURLWithPath: "/tmp/a.fit")
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 60, distanceMeters: 200)
        ])

        model.upsertActivityAsset(url: url, series: series)
        model.upsertActivityAsset(url: url, series: series) // dedup
        XCTAssertEqual(model.activityAssets.count, 1)
        XCTAssertEqual(model.activityAssets[0].kind, .activity)
        XCTAssertEqual(model.activityAssets[0].duration, 60)
        XCTAssertNil(model.activeActivityAssetID)

        model.fitURL = url
        XCTAssertEqual(model.activeActivityAssetID, "/tmp/a.fit")
    }

    func testCustomTimelinePreviewRendersOverlayWithoutVideo() async {
        let model = StudioModel()
        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 60, distanceMeters: 300)
        ]))
        model.fitURL = activeURL

        let pooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: pooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.previewTime = 12
        model.addActivityAssetToTimeline(id: pooledURL.path)

        model.refreshPreview()
        await waitForOverlayPreview(model)

        XCTAssertNil(model.backgroundImage)
        XCTAssertNotNil(model.overlayImage)
        XCTAssertNil(model.previewWarning)
    }

    func testCustomTimelineCanvasPrefersRenderedFrameOverSingleSourcePlayer() {
        let model = StudioModel()
        let activeURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: activeURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 60, distanceMeters: 300)
        ]))
        model.fitURL = activeURL

        let pooledURL = URL(fileURLWithPath: "/tmp/b.fit")
        model.upsertActivityAsset(url: pooledURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.previewTime = 12
        model.addActivityAssetToTimeline(id: pooledURL.path)
        model.player = AVPlayer()

        let state = PreviewCanvasState(model: model)

        XCTAssertNil(state.player)
    }

    private func waitForOverlayPreview(
        _ model: StudioModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if model.overlayImage != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Expected overlay preview to render.", file: file, line: line)
    }
}
