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

    func testQueuedVideoImportsWaitForSelectionOrderAndAppendToExistingTimeline() {
        let model = StudioModel()
        let activityURL = URL(fileURLWithPath: "/tmp/existing.fit")
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 30, distanceMeters: 100)
        ]))
        model.fitURL = activityURL

        let firstURL = URL(fileURLWithPath: "/tmp/import-1.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/import-2.mov")
        model.queueImportedVideosForTimeline([firstURL, secondURL])

        model.upsertVideoAsset(
            url: secondURL,
            metadata: videoMetadata(width: 1280, height: 720, duration: 20, fps: 30)
        )
        XCTAssertTrue(model.currentTimelineProject.tracks.filter { $0.kind == .video }.isEmpty)

        model.upsertVideoAsset(
            url: firstURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 10, fps: 30)
        )

        let videoTracks = model.currentTimelineProject.tracks.filter { $0.kind == .video }
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(videoTracks[0].clips.map(\.assetID), [firstURL.path, secondURL.path])
        XCTAssertEqual(videoTracks[0].clips[0].timelineStart, 30, accuracy: 1e-9)
        XCTAssertEqual(videoTracks[0].clips[1].timelineStart, 40, accuracy: 1e-9)
    }

    func testQueuedVideoImportsStartAtZeroWhenTimelineIsEmpty() {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/empty-import-1.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/empty-import-2.mov")
        model.queueImportedVideosForTimeline([firstURL, secondURL])

        // The first selected file becomes the active source before its metadata is inserted.
        model.videoURL = firstURL
        model.upsertVideoAsset(
            url: secondURL,
            metadata: videoMetadata(width: 1280, height: 720, duration: 20, fps: 30)
        )
        model.upsertVideoAsset(
            url: firstURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 10, fps: 30)
        )

        let videoTracks = model.currentTimelineProject.tracks.filter { $0.kind == .video }
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(videoTracks[0].clips.map(\.assetID), [firstURL.path, secondURL.path])
        XCTAssertEqual(videoTracks[0].clips[0].timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(videoTracks[0].clips[1].timelineStart, 10, accuracy: 1e-9)
    }

    func testQueuedActivityImportsWaitForSelectionOrderAndReuseOneOverlayTrack() {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/existing.mov")
        model.upsertVideoAsset(
            url: videoURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 50, fps: 30)
        )
        model.videoURL = videoURL

        let firstURL = URL(fileURLWithPath: "/tmp/import-1.fit")
        let secondURL = URL(fileURLWithPath: "/tmp/import-2.fit")
        model.queueImportedActivitiesForTimeline([firstURL, secondURL])

        model.upsertActivityAsset(url: secondURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 20, distanceMeters: 100)
        ]))
        XCTAssertTrue(model.currentTimelineProject.tracks.filter { $0.kind == .overlay }.isEmpty)

        model.upsertActivityAsset(url: firstURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 50)
        ]))

        let overlayTracks = model.currentTimelineProject.tracks.filter { $0.kind == .overlay }
        XCTAssertEqual(overlayTracks.count, 1)
        XCTAssertEqual(overlayTracks[0].clips.map(\.assetID), [firstURL.path, secondURL.path])
        XCTAssertEqual(overlayTracks[0].clips[0].timelineStart, 50, accuracy: 1e-9)
        XCTAssertEqual(overlayTracks[0].clips[1].timelineStart, 60, accuracy: 1e-9)
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
        model.addActivityAssetToTimeline(id: secondURL.path)

        let overlayClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
        XCTAssertEqual(overlayClips.count, 2)
        XCTAssertEqual(overlayClips.last?.assetID, secondURL.path)
        XCTAssertEqual(overlayClips.last?.timelineStart ?? -1, 120, accuracy: 1e-9)
        XCTAssertEqual(
            model.currentTimelineProject.tracks.filter { $0.kind == .overlay }.count,
            1
        )

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
        XCTAssertEqual(overlayTracks.count, 1)

        let updatedTrack = try XCTUnwrap(overlayTracks.first { $0.id == targetTrack.id })
        XCTAssertEqual(updatedTrack.clips.count, 3)
        XCTAssertEqual(updatedTrack.clips.last?.assetID, secondPooledURL.path)
        // The drop point sits inside the occupied [0, 125) span, so the clip lands after it.
        XCTAssertEqual(updatedTrack.clips.last?.timelineStart ?? -1, 125, accuracy: 1e-9)
    }

    func testMatchPointHelperWritesCanonicalSync() {
        let model = StudioModel()
        model.videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.fitURL = URL(fileURLWithPath: "/tmp/a.fit")

        // Place the canonical activity-zero match point at video 30s.
        model.setActivitySyncZeroVideoTime(30)
        XCTAssertEqual(model.syncVideoSeconds, 30, accuracy: 1e-9)
        XCTAssertEqual(model.syncFITSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, 30, accuracy: 1e-9)

        // Activity begins before the video source starts.
        model.setActivitySyncZeroVideoTime(-12)
        XCTAssertEqual(model.syncVideoSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(model.syncFITSeconds, 12, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, -12, accuracy: 1e-9)
    }

    func testSingleSourceVideoAndActivityClipsMoveIndependentlyAndAllowLeadingBlank() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        let activityURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertVideoAsset(
            url: videoURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30)
        )
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.videoURL = videoURL
        model.fitURL = activityURL
        model.syncVideoSeconds = 10
        model.syncFITSeconds = 40
        model.setExportTrimEnd(60)

        let originalSync = model.timeSync
        model.moveTimelineClip(id: "single.video.clip", toTimelineStart: 25)
        model.moveTimelineClip(id: "single.overlay.clip", toTimelineStart: 12)

        let project = model.currentTimelineProject
        let video = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.video.clip" })
        let activity = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.overlay.clip" })
        XCTAssertEqual(video.timelineStart, 25, accuracy: 1e-9)
        XCTAssertEqual(activity.timelineStart, 12, accuracy: 1e-9)
        XCTAssertEqual(model.timeSync, originalSync)
        XCTAssertEqual(model.effectiveExportTrimEnd, 60, accuracy: 1e-9)
        XCTAssertEqual(
            project.sourceMatchPoint,
            TimelineSourceMatchPoint(
                videoAssetID: videoURL.path,
                activityAssetID: activityURL.path,
                videoSourceTime: 10,
                activitySourceTime: 40
            )
        )
        XCTAssertTrue(model.usesCustomTimelinePreview)
        XCTAssertTrue(project.activeClips(kind: .video, atTimelineTime: 0).isEmpty)
        XCTAssertTrue(project.activeClips(kind: .overlay, atTimelineTime: 0).isEmpty)
    }

    func testMatchPointInputsRealignSingleSourceClipsByRelativeSourceTimes() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        let activityURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertVideoAsset(
            url: videoURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30)
        )
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.videoURL = videoURL
        model.fitURL = activityURL

        model.syncVideoSeconds = 10
        model.syncFITSeconds = 40

        var project = model.currentTimelineProject
        var video = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.video.clip" })
        var activity = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.overlay.clip" })
        XCTAssertEqual(video.timelineStart, 30, accuracy: 1e-9)
        XCTAssertEqual(activity.timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(video.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(activity.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(video.timelineTime(forSourceTime: 10), activity.timelineTime(forSourceTime: 40), accuracy: 1e-9)

        model.moveTimelineClip(id: video.id, toTimelineStart: 50)
        model.syncFITSeconds = 35

        project = model.currentTimelineProject
        video = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.video.clip" })
        activity = try XCTUnwrap(project.tracks.flatMap(\.clips).first { $0.id == "single.overlay.clip" })
        XCTAssertEqual(video.timelineStart, 50, accuracy: 1e-9)
        XCTAssertEqual(activity.timelineStart, 25, accuracy: 1e-9)
        XCTAssertEqual(video.timelineTime(forSourceTime: 10), activity.timelineTime(forSourceTime: 35), accuracy: 1e-9)
    }

    func testRelativeMatchPointPreviewUsesTimelineAndReportsSourceVideoTime() {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        let activityURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertVideoAsset(
            url: videoURL,
            metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30)
        )
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 300, distanceMeters: 1_000)
        ]))
        model.videoURL = videoURL
        model.sourceDuration = 120
        model.exportTrimEndSeconds = 120
        model.fitURL = activityURL
        model.syncVideoSeconds = 10
        model.syncFITSeconds = 40

        XCTAssertTrue(model.usesCustomTimelinePreview)
        XCTAssertEqual(model.previewDuration, 300, accuracy: 1e-9)
        XCTAssertEqual(model.effectiveExportTrimStart, 0, accuracy: 1e-9)
        XCTAssertEqual(model.effectiveExportTrimEnd, 300, accuracy: 1e-9)
        model.previewTime = 0
        XCTAssertNil(model.currentVideoSourceTimeForSync)
        model.previewTime = 45
        XCTAssertEqual(model.currentVideoSourceTimeForSync ?? -1, 15, accuracy: 1e-9)
    }

    func testLoadingTimelineRestoresSourceMatchPointWithoutMovingEditedClips() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        let activityURL = URL(fileURLWithPath: "/tmp/a.fit")
        let video = MediaAsset(
            id: videoURL.path,
            kind: .video,
            url: videoURL,
            displayName: videoURL.lastPathComponent,
            duration: 120
        )
        let activity = MediaAsset(
            id: activityURL.path,
            kind: .activity,
            url: activityURL,
            displayName: activityURL.lastPathComponent,
            duration: 300
        )
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [video, activity],
            tracks: [
                TimelineTrack(
                    id: "video",
                    kind: .video,
                    name: "V1",
                    clips: [TimelineClip(id: "video-clip", assetID: video.id, timelineStart: 25, duration: 120)]
                ),
                TimelineTrack(
                    id: "overlay",
                    kind: .overlay,
                    name: "O1",
                    clips: [TimelineClip(id: "activity-clip", assetID: activity.id, timelineStart: 12, duration: 300)]
                )
            ],
            sourceMatchPoint: TimelineSourceMatchPoint(
                videoAssetID: video.id,
                activityAssetID: activity.id,
                videoSourceTime: 10,
                activitySourceTime: 40
            )
        )

        model.applyTimelineProject(project, loadAssets: false)

        XCTAssertEqual(model.syncVideoSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(model.syncFITSeconds, 40, accuracy: 1e-9)
        let loadedVideo = try XCTUnwrap(model.currentTimelineProject.tracks.flatMap(\.clips).first { $0.id == "video-clip" })
        let loadedActivity = try XCTUnwrap(model.currentTimelineProject.tracks.flatMap(\.clips).first { $0.id == "activity-clip" })
        XCTAssertEqual(loadedVideo.timelineStart, 25, accuracy: 1e-9)
        XCTAssertEqual(loadedActivity.timelineStart, 12, accuracy: 1e-9)
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

        model.moveTimelineClip(id: customClip.id, toTimelineStart: 95)

        let movedClip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.id == customClip.id }
        )
        XCTAssertEqual(movedClip.timelineStart, 95, accuracy: 1e-9)
        XCTAssertEqual(model.activitySyncZeroVideoTime, 10, accuracy: 1e-9)
    }

    func testAddingPooledVideoAppendsToVideoTrack() throws {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL
        let activityURL = URL(fileURLWithPath: "/tmp/longer.fit")
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 150, distanceMeters: 300)
        ]))
        model.fitURL = activityURL

        model.addVideoAssetToTimeline(id: secondURL.path)

        let videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.count, 2)
        XCTAssertEqual(videoClips[0].assetID, firstURL.path)
        XCTAssertEqual(videoClips[1].assetID, secondURL.path)
        XCTAssertEqual(videoClips[1].timelineStart, 150, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].duration, 40, accuracy: 1e-9)
    }

    func testAddingPooledVideoCanDropOnTargetTrackAtRelativePosition() throws {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/drop-video-a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/drop-video-b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL

        let targetTrack = try XCTUnwrap(
            model.currentTimelineProject.tracks.first { $0.kind == .video }
        )
        model.addVideoAssetToTimeline(
            id: secondURL.path,
            targetTrackID: targetTrack.id,
            timelineStart: 40
        )

        let updatedTrack = try XCTUnwrap(
            model.currentTimelineProject.tracks.first { $0.id == targetTrack.id }
        )
        XCTAssertEqual(updatedTrack.clips.count, 2)
        XCTAssertEqual(updatedTrack.clips.last?.assetID, secondURL.path)
        XCTAssertEqual(updatedTrack.clips.last?.timelineStart ?? -1, 100, accuracy: 1e-9)
    }

    func testTimelineAssetIDsInUseIncludesEveryReferencedVideoAndActivity() {
        let model = StudioModel()
        let firstVideoURL = URL(fileURLWithPath: "/tmp/in-use-video-a.mov")
        let secondVideoURL = URL(fileURLWithPath: "/tmp/in-use-video-b.mov")
        let firstActivityURL = URL(fileURLWithPath: "/tmp/in-use-activity-a.fit")
        let secondActivityURL = URL(fileURLWithPath: "/tmp/in-use-activity-b.fit")

        model.upsertVideoAsset(url: firstVideoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondVideoURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.upsertActivityAsset(url: firstActivityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.upsertActivityAsset(url: secondActivityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 45, distanceMeters: 180)
        ]))
        model.videoURL = firstVideoURL
        model.fitURL = firstActivityURL
        model.addVideoAssetToTimeline(id: secondVideoURL.path)
        model.addActivityAssetToTimeline(id: secondActivityURL.path)

        XCTAssertEqual(
            model.timelineAssetIDsInUse,
            Set([
                firstVideoURL.path,
                secondVideoURL.path,
                firstActivityURL.path,
                secondActivityURL.path
            ])
        )
    }

    func testOnlyEmptyTimelineTracksCanBeRemoved() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
        let videoURL = URL(fileURLWithPath: "/tmp/occupied-track.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 30, fps: 30))
        model.videoURL = videoURL

        let occupiedTrackID = try XCTUnwrap(
            model.currentTimelineProject.tracks.first { $0.kind == .video }?.id
        )
        model.removeEmptyTimelineTrack(id: occupiedTrackID)
        XCTAssertTrue(model.currentTimelineProject.tracks.contains { $0.id == occupiedTrackID })

        let clipID = try XCTUnwrap(
            model.currentTimelineProject.tracks.first { $0.id == occupiedTrackID }?.clips.first?.id
        )
        model.deleteTimelineClip(id: clipID, ripple: false)
        XCTAssertTrue(
            model.currentTimelineProject.tracks.contains { $0.id == occupiedTrackID && $0.clips.isEmpty }
        )

        model.removeEmptyTimelineTrack(id: occupiedTrackID)

        XCTAssertFalse(model.currentTimelineProject.tracks.contains { $0.id == occupiedTrackID })

        undoManager.undo()

        XCTAssertTrue(
            model.currentTimelineProject.tracks.contains { $0.id == occupiedTrackID && $0.clips.isEmpty }
        )
    }

    func testTimelineDragPayloadSupportsVideoAndActivityAssets() {
        let videoPayload = TimelineDragPayload.video(assetID: "/tmp/video.mov")
        let activityPayload = TimelineDragPayload.activity(assetID: "/tmp/activity.fit")

        XCTAssertEqual(TimelineDragPayload.videoAssetID(from: videoPayload), "/tmp/video.mov")
        XCTAssertNil(TimelineDragPayload.activityAssetID(from: videoPayload))
        XCTAssertEqual(TimelineDragPayload.activityAssetID(from: activityPayload), "/tmp/activity.fit")
        XCTAssertNil(TimelineDragPayload.videoAssetID(from: activityPayload))
    }

    func testCustomTimelineSourceSelectionRequiresConfirmationBeforeReplacingTimeline() {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL
        model.addVideoAssetToTimeline(id: secondURL.path)
        let originalTimeline = model.currentTimelineProject

        model.selectVideoAsset(id: secondURL.path)

        XCTAssertEqual(model.pendingTimelineAction, .selectVideoAsset(id: secondURL.path))
        XCTAssertEqual(model.currentTimelineProject, originalTimeline)

        model.cancelPendingTimelineAction()

        XCTAssertNil(model.pendingTimelineAction)
        XCTAssertEqual(model.currentTimelineProject, originalTimeline)
    }

    func testRemovingReferencedAssetRequiresConfirmationAndKeepsProjectDirty() {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/a.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/b.mov")
        model.upsertVideoAsset(url: firstURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 100, fps: 30))
        model.upsertVideoAsset(url: secondURL, metadata: videoMetadata(width: 1280, height: 720, duration: 40, fps: 30))
        model.videoURL = firstURL
        model.addVideoAssetToTimeline(id: secondURL.path)
        let originalTimeline = model.currentTimelineProject

        model.removeVideoAsset(id: secondURL.path)

        XCTAssertEqual(model.pendingTimelineAction, .removeVideoAsset(id: secondURL.path))
        XCTAssertEqual(model.currentTimelineProject, originalTimeline)
        XCTAssertTrue(model.videoAssets.contains { $0.id == secondURL.path })

        XCTAssertEqual(model.confirmPendingTimelineAction(), .removeVideoAsset(id: secondURL.path))
        XCTAssertFalse(model.videoAssets.contains { $0.id == secondURL.path })
        XCTAssertFalse(model.currentTimelineProject.assets.contains { $0.id == secondURL.path })
        XCTAssertTrue(model.hasUnsavedTimelineChanges)
    }

    func testApplyingProjectMarksItCleanAndEditingMarksItDirty() throws {
        let model = StudioModel()
        let activityURL = URL(fileURLWithPath: "/tmp/activity.fit")
        let activity = MediaAsset(
            id: activityURL.path,
            kind: .activity,
            url: activityURL,
            displayName: activityURL.lastPathComponent,
            duration: 30
        )
        let clip = TimelineClip(
            id: "overlay.clip",
            assetID: activity.id,
            timelineStart: 0,
            duration: 30
        )
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [activity],
            tracks: [TimelineTrack(id: "overlay.track", kind: .overlay, name: "O1", clips: [clip])]
        )

        model.applyTimelineProject(project, loadAssets: false)
        XCTAssertFalse(model.hasUnsavedTimelineChanges)

        model.moveTimelineClip(id: clip.id, toTimelineStart: 5)
        XCTAssertTrue(model.hasUnsavedTimelineChanges)
    }

    func testDirtyTimelineDefersOpenAndWindowCloseUntilConfirmed() {
        let model = StudioModel()
        let activityURL = URL(fileURLWithPath: "/tmp/activity.fit")
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 30, distanceMeters: 100)
        ]))
        model.fitURL = activityURL
        model.addActivityAssetToTimeline(id: activityURL.path)
        XCTAssertTrue(model.hasUnsavedTimelineChanges)

        model.openTimelineProject()
        XCTAssertEqual(model.pendingTimelineAction, .openTimelineProject)
        model.cancelPendingTimelineAction()

        XCTAssertFalse(model.requestWindowClose())
        XCTAssertEqual(model.pendingTimelineAction, .closeWindow)
        XCTAssertEqual(model.confirmPendingTimelineAction(), .closeWindow)
        XCTAssertTrue(model.requestWindowClose())
    }

    func testCustomTimelineExportReadinessUsesTimelineTelemetryInsteadOfLegacyActiveSeries() {
        let model = StudioModel()
        let activityURL = URL(fileURLWithPath: "/tmp/activity.fit")
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 30, distanceMeters: 100)
        ]))
        model.fitURL = activityURL
        model.addActivityAssetToTimeline(id: activityURL.path)
        model.series = nil

        XCTAssertTrue(model.canExport(as: .overlay))
        XCTAssertNil(model.exportReadinessMessage(for: .overlay))
    }

    func testCustomTimelineExportReadinessAllowsSparseVideoClips() {
        let model = StudioModel()
        let firstVideo = MediaAsset(
            id: "video-a",
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/a.mov"),
            displayName: "a.mov",
            duration: 2
        )
        let secondVideo = MediaAsset(
            id: "video-b",
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/b.mov"),
            displayName: "b.mov",
            duration: 2
        )
        let activityURL = URL(fileURLWithPath: "/tmp/activity.fit")
        let activity = MediaAsset(
            id: activityURL.path,
            kind: .activity,
            url: activityURL,
            displayName: activityURL.lastPathComponent,
            duration: 3
        )
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [firstVideo, secondVideo, activity],
            tracks: [
                TimelineTrack(id: "video", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "video-a", assetID: firstVideo.id, timelineStart: 0, duration: 1),
                    TimelineClip(id: "video-b", assetID: secondVideo.id, timelineStart: 1.5, duration: 1)
                ]),
                TimelineTrack(id: "overlay", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "activity", assetID: activity.id, timelineStart: 0, duration: 2.5)
                ])
            ]
        )
        model.applyTimelineProject(project, loadAssets: false)
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 3, distanceMeters: 10)
        ]))

        XCTAssertTrue(model.canExport(as: .video))
        XCTAssertNil(model.exportReadinessMessage(for: .video))
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

    func testTimelineProjectJSONRoundTripsIntoStoredCustomTimeline() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/project-video.mov")
        let activityURL = URL(fileURLWithPath: "/tmp/project-activity.fit")
        let videoAsset = MediaAsset(
            id: videoURL.path,
            kind: .video,
            url: videoURL,
            displayName: "project-video.mov",
            duration: 40,
            width: 1920,
            height: 1080,
            framesPerSecond: 30
        )
        let activityAsset = MediaAsset(
            id: activityURL.path,
            kind: .activity,
            url: activityURL,
            displayName: "project-activity.fit",
            duration: 30
        )
        let project = TimelineProject(
            outputWidth: 1280,
            outputHeight: 720,
            framesPerSecond: 24,
            distanceUnit: .meters,
            assets: [videoAsset, activityAsset],
            tracks: [
                TimelineTrack(
                    id: "video.track.custom",
                    kind: .video,
                    name: "V1",
                    clips: [
                        TimelineClip(
                            id: "video.clip.custom",
                            assetID: videoAsset.id,
                            timelineStart: 0,
                            duration: 40
                        )
                    ]
                ),
                TimelineTrack(
                    id: "overlay.track.custom",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "overlay.clip.custom",
                            assetID: activityAsset.id,
                            timelineStart: 5,
                            duration: 20,
                            sourceIn: 3,
                            layout: .default,
                            distanceUnit: .kilometers
                        )
                    ]
                )
            ]
        )
        let data = try JSONEncoder().encode(project)

        try model.loadTimelineProject(from: data, loadAssets: false)

        XCTAssertEqual(model.currentTimelineProject.assets, project.assets)
        XCTAssertEqual(model.currentTimelineProject.tracks, project.tracks)
        XCTAssertEqual(model.videoAssets, [videoAsset])
        XCTAssertEqual(model.activityAssets, [activityAsset])
        XCTAssertEqual(model.videoURL, videoURL)
        XCTAssertEqual(model.fitURL, activityURL)
        XCTAssertEqual(model.outputWidth, 1280)
        XCTAssertEqual(model.outputHeight, 720)
        XCTAssertEqual(model.outputFPS, 24)
        XCTAssertEqual(model.distanceUnit, .meters)

        let saved = try JSONDecoder().decode(TimelineProject.self, from: model.timelineProjectJSONData())
        XCTAssertEqual(saved.tracks, model.currentTimelineProject.tracks)
        XCTAssertEqual(saved.outputWidth, model.currentTimelineProject.outputWidth)
        XCTAssertEqual(saved.outputHeight, model.currentTimelineProject.outputHeight)
        XCTAssertEqual(saved.framesPerSecond, model.currentTimelineProject.framesPerSecond)
        XCTAssertEqual(saved.distanceUnit, model.currentTimelineProject.distanceUnit)
        XCTAssertEqual(saved.assets.map(\.id), model.currentTimelineProject.assets.map(\.id))

        model.setOutputWidth(1920)

        XCTAssertEqual(model.currentTimelineProject.tracks, project.tracks)
        XCTAssertEqual(model.currentTimelineProject.assets, project.assets)
        XCTAssertEqual(model.currentTimelineProject.outputWidth, 1920)
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

        model.trimTimelineClipStart(id: clip.id, toTimelineTime: 125)
        model.trimTimelineClipEnd(id: clip.id, toTimelineTime: 160)

        let trimmed = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.id == clip.id }
        )
        XCTAssertEqual(trimmed.timelineStart, 125, accuracy: 1e-9)
        XCTAssertEqual(trimmed.sourceIn, 5, accuracy: 1e-9)
        XCTAssertEqual(trimmed.duration, 35, accuracy: 1e-9)
    }

    func testSplittingClipsAtPlayheadCutsVideoAndOverlay() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL
        let fitURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: fitURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = fitURL

        model.previewTime = 30
        XCTAssertTrue(model.canSplitTimelineClipsAtPlayhead)
        model.splitTimelineClipsAtPlayhead()

        let videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.count, 2)
        XCTAssertEqual(videoClips[0].timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(videoClips[0].duration, 30, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].timelineStart, 30, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].duration, 90, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].sourceIn, 30, accuracy: 1e-9)
        XCTAssertNotEqual(videoClips[0].id, videoClips[1].id)

        let overlayClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
        XCTAssertEqual(overlayClips.count, 2)
        XCTAssertEqual(overlayClips[1].timelineStart, 30, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[1].sourceIn, 30, accuracy: 1e-9)

        // Splitting is a real edit: the timeline is now the custom, stored one.
        XCTAssertTrue(model.usesCustomTimelinePreview)
    }

    func testDeletingTimelineClipLeavesGap() throws {
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
        model.selectTimelineClip(id: clip.id)
        XCTAssertTrue(model.canDeleteTimelineClip(id: clip.id))

        model.deleteSelectedTimelineClip(ripple: false)

        XCTAssertNil(model.selectedTimelineClipID)
        let remaining = model.currentTimelineProject.tracks.flatMap(\.clips)
        XCTAssertFalse(remaining.contains { $0.id == clip.id })
        // A plain delete leaves the gap: nothing else moves.
        let videoClip = try XCTUnwrap(remaining.first { $0.assetID == videoURL.path })
        XCTAssertEqual(videoClip.timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(videoClip.duration, 120, accuracy: 1e-9)
        let activeOverlay = try XCTUnwrap(remaining.first { $0.assetID == activeURL.path })
        XCTAssertEqual(activeOverlay.timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(activeOverlay.duration, 80, accuracy: 1e-9)
    }

    func testRippleDeletingTimelineClipClosesGapAcrossTracks() throws {
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

        // Default insertion appends after the 120-second project. Ripple deletion removes that
        // trailing range without disturbing clips that already end before it.
        model.deleteTimelineClip(id: clip.id, ripple: true)

        let videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.count, 1)
        XCTAssertEqual(videoClips[0].timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(videoClips[0].duration, 120, accuracy: 1e-9)

        let overlayClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
        XCTAssertEqual(overlayClips.count, 1)
        XCTAssertEqual(overlayClips[0].timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[0].duration, 80, accuracy: 1e-9)

        XCTAssertEqual(model.currentTimelineProject.duration, 120, accuracy: 1e-9)
    }

    func testTimelineEditsSupportUndoAndRedo() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        // Tests have no run-loop event boundaries; disable event grouping so each explicit
        // undo group stands alone, matching the per-event grouping the app gets at runtime.
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL
        let fitURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: fitURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = fitURL

        func videoClips() -> [TimelineClip] {
            model.currentTimelineProject.tracks
                .filter { $0.kind == .video }
                .flatMap(\.clips)
        }

        model.previewTime = 30
        model.splitTimelineClipsAtPlayhead()
        XCTAssertEqual(videoClips().count, 2)
        XCTAssertTrue(model.usesCustomTimelinePreview)
        XCTAssertTrue(undoManager.canUndo)

        // Undo restores the unsplit timeline and the single-source preview mode.
        undoManager.undo()
        XCTAssertEqual(videoClips().count, 1)
        XCTAssertFalse(model.usesCustomTimelinePreview)

        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(videoClips().count, 2)

        // Undo of a delete restores the clip and its selection.
        let clip = try XCTUnwrap(videoClips().first)
        model.selectTimelineClip(id: clip.id)
        model.deleteTimelineClip(id: clip.id, ripple: false)
        XCTAssertEqual(videoClips().count, 1)
        XCTAssertNil(model.selectedTimelineClipID)

        undoManager.undo()
        XCTAssertEqual(videoClips().count, 2)
        XCTAssertEqual(model.selectedTimelineClipID, clip.id)
    }

    func testDraggedMoveCoalescesIntoOneUndoStep() throws {
        let model = StudioModel()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
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
        model.previewTime = 0
        model.addActivityAssetToTimeline(id: pooledURL.path)

        let clip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first { $0.assetID == pooledURL.path }
        )

        // Rapid-fire updates from one drag collapse into a single undo step.
        model.moveTimelineClip(id: clip.id, toTimelineStart: 65)
        model.moveTimelineClip(id: clip.id, toTimelineStart: 70)
        model.moveTimelineClip(id: clip.id, toTimelineStart: 75)

        undoManager.undo()
        let restored = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .flatMap(\.clips)
                .first { $0.id == clip.id }
        )
        XCTAssertEqual(restored.timelineStart, 60, accuracy: 1e-9)
    }

    func testMovingAndTrimmingClipsCannotOverlapOnSameTrack() throws {
        let model = StudioModel()
        let videoURL = URL(fileURLWithPath: "/tmp/a.mov")
        model.upsertVideoAsset(url: videoURL, metadata: videoMetadata(width: 1920, height: 1080, duration: 120, fps: 30))
        model.videoURL = videoURL
        let fitURL = URL(fileURLWithPath: "/tmp/a.fit")
        model.upsertActivityAsset(url: fitURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 80, distanceMeters: 300)
        ]))
        model.fitURL = fitURL

        // Split the video at 60 so V1 holds two adjacent clips [0,60) + [60,120).
        model.previewTime = 60
        model.splitTimelineClipsAtPlayhead()
        var videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.count, 2)
        let firstID = videoClips[0].id
        let secondID = videoClips[1].id

        // Move the second clip to make room, then try to drag it back onto the first clip:
        // it clamps to the first clip's right edge instead of overlapping.
        model.moveTimelineClip(id: secondID, toTimelineStart: 100)
        model.moveTimelineClip(id: secondID, toTimelineStart: 30)
        videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        XCTAssertEqual(videoClips.first { $0.id == secondID }?.timelineStart ?? -1, 60, accuracy: 1e-9)

        // With the second clip back at 100, the first clip cannot trim its end into it.
        model.moveTimelineClip(id: secondID, toTimelineStart: 100)
        model.trimTimelineClipEnd(id: firstID, toTimelineTime: 110)
        videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        let first = try XCTUnwrap(videoClips.first { $0.id == firstID })
        XCTAssertEqual(first.timelineEnd, 100, accuracy: 1e-9)

        // The second clip cannot trim its start into the first clip either.
        model.trimTimelineClipStart(id: secondID, toTimelineTime: 90)
        videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        let second = try XCTUnwrap(videoClips.first { $0.id == secondID })
        XCTAssertEqual(second.timelineStart, 100, accuracy: 1e-9)

        // The inspector cannot create overlaps: duration caps at the next clip.
        model.setTimelineClipTiming(id: firstID, timelineStart: 0, duration: 120)
        videoClips = model.currentTimelineProject.tracks
            .filter { $0.kind == .video }
            .flatMap(\.clips)
        let capped = try XCTUnwrap(videoClips.first { $0.id == firstID })
        XCTAssertEqual(capped.duration, 100, accuracy: 1e-9)
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

        model.setTimelineClipTiming(id: clip.id, timelineStart: 70, sourceIn: 4, duration: 20)
        model.setTimelineClipDistanceUnit(id: clip.id, .meters)

        var customLayout = model.layout
        customLayout.elements[0].frame.x = 0.42
        model.setTimelineClipLayout(id: clip.id, customLayout)

        let edited = try XCTUnwrap(model.selectedTimelineClip)
        XCTAssertEqual(edited.timelineStart, 70, accuracy: 1e-9)
        XCTAssertEqual(edited.sourceIn, 4, accuracy: 1e-9)
        XCTAssertEqual(edited.duration, 20, accuracy: 1e-9)
        XCTAssertEqual(edited.distanceUnit, .meters)
        XCTAssertEqual(try XCTUnwrap(edited.layout?.elements[0].frame.x), 0.42, accuracy: 1e-9)

        let elementID = try XCTUnwrap(model.layout.elements.first?.id)
        model.selectElement(id: elementID)
        XCTAssertNil(model.selectedTimelineClipID)
        XCTAssertEqual(model.selectedElement?.id, elementID)
    }

    func testDistanceUnitForCurrentSelectionReadsAndWritesSelectedActivityClip() throws {
        let model = StudioModel()
        let originalDistanceUnit = model.distanceUnit
        defer { model.distanceUnit = originalDistanceUnit }
        model.distanceUnit = .kilometers

        let activityURL = URL(fileURLWithPath: "/tmp/contextual-unit.fit")
        model.upsertActivityAsset(url: activityURL, series: TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 60, distanceMeters: 1_000)
        ]))
        model.fitURL = activityURL

        let clip = try XCTUnwrap(
            model.currentTimelineProject.tracks
                .filter { $0.kind == .overlay }
                .flatMap(\.clips)
                .first
        )
        model.selectTimelineClip(id: clip.id)
        model.setTimelineClipDistanceUnit(id: clip.id, .meters)

        XCTAssertEqual(model.distanceUnitForCurrentSelection, .meters)
        XCTAssertEqual(model.distanceUnit, .kilometers)

        model.setDistanceUnitForCurrentSelection(.kilometers)

        XCTAssertEqual(model.selectedTimelineClip?.distanceUnit, .kilometers)
        XCTAssertEqual(model.distanceUnit, .kilometers)

        model.selectedTimelineClipID = nil
        model.setDistanceUnitForCurrentSelection(.meters)

        XCTAssertEqual(model.distanceUnitForCurrentSelection, .meters)
        XCTAssertEqual(model.distanceUnit, .meters)
    }

    func testMatchPointHelperIsIgnoredWithoutBothSources() {
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

    func testCustomTimelineCanvasUsesSharedPlayerAndTearsDownWithoutVideo() {
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
        model.player = AVPlayer()
        // Entering custom-timeline mode with no video clips tears the player down so the
        // overlay clock and frame rendering drive the preview.
        model.addActivityAssetToTimeline(id: pooledURL.path)
        XCTAssertNil(model.player)

        // The canvas mirrors the shared player: composition-backed playback shows through it.
        model.player = AVPlayer()
        let state = PreviewCanvasState(model: model)
        XCTAssertNotNil(state.player)
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
