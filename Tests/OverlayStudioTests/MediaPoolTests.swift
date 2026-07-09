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
}
