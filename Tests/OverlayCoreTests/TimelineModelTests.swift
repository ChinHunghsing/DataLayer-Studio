import XCTest
import OverlayCore

final class TimelineModelTests: XCTestCase {
    private func videoAsset(id: String = "vid", duration: TimeInterval) -> MediaAsset {
        MediaAsset(
            id: id, kind: .video, url: URL(fileURLWithPath: "/tmp/\(id).mov"),
            displayName: "\(id).mov", duration: duration,
            width: 1920, height: 1080, framesPerSecond: 30
        )
    }

    private func activityAsset(id: String = "act", duration: TimeInterval) -> MediaAsset {
        MediaAsset(
            id: id, kind: .activity, url: URL(fileURLWithPath: "/tmp/\(id).fit"),
            displayName: "\(id).fit", duration: duration
        )
    }

    // MARK: clip geometry

    func testClipSourceTimeMappingAndContainment() {
        let clip = TimelineClip(id: "c", assetID: "a", timelineStart: 10, duration: 20, sourceIn: 5)
        XCTAssertEqual(clip.timelineEnd, 30)
        XCTAssertFalse(clip.contains(timelineTime: 9.99))
        XCTAssertTrue(clip.contains(timelineTime: 10))
        XCTAssertTrue(clip.contains(timelineTime: 29.99))
        XCTAssertFalse(clip.contains(timelineTime: 30)) // exclusive end
        // source time = sourceIn + (t - start)
        XCTAssertEqual(clip.sourceTime(atTimelineTime: 10), 5)
        XCTAssertEqual(clip.sourceTime(atTimelineTime: 25), 20)
    }

    func testTrackClipLookupPrefersLastOverlapping() {
        let a = TimelineClip(id: "a", assetID: "x", timelineStart: 0, duration: 10)
        let b = TimelineClip(id: "b", assetID: "x", timelineStart: 5, duration: 10)
        let track = TimelineTrack(id: "t", kind: .overlay, name: "O1", clips: [a, b])
        XCTAssertEqual(track.clip(atTimelineTime: 2)?.id, "a")
        XCTAssertEqual(track.clip(atTimelineTime: 7)?.id, "b") // overlap -> last wins
        XCTAssertNil(track.clip(atTimelineTime: 20))
    }

    func testProjectDurationIsFurthestClipEnd() {
        let project = TimelineProject(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            assets: [],
            tracks: [
                TimelineTrack(id: "v", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "vc", assetID: "vid", timelineStart: 0, duration: 130)
                ]),
                TimelineTrack(id: "o", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "oc", assetID: "act", timelineStart: 40, duration: 110)
                ])
            ]
        )
        XCTAssertEqual(project.duration, 150) // 40 + 110
    }

    // MARK: Codable

    func testProjectCodableRoundTrip() throws {
        let original = TimelineProject.migratingSingleSource(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            videoAsset: videoAsset(duration: 120),
            activityAsset: activityAsset(duration: 300),
            sync: TelemetryTimeSync(videoSyncTime: 10, fitSyncTime: 40),
            layout: .default,
            clipIDProvider: { "clip" }, trackIDProvider: { "track" }
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: migration reproduces the sync mapping

    func testMigrationVideoAndActivityPositiveOffset() {
        let sync = TelemetryTimeSync(videoSyncTime: 10, fitSyncTime: 40) // offset +30 (activity ahead)
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            videoAsset: videoAsset(duration: 120),
            activityAsset: activityAsset(duration: 300),
            sync: sync, layout: .default
        )
        XCTAssertEqual(project.tracks.count, 2)
        XCTAssertEqual(project.tracks[0].kind, .video)   // base
        XCTAssertEqual(project.tracks[1].kind, .overlay) // on top

        let videoClip = project.tracks[0].clips[0]
        XCTAssertEqual(videoClip.timelineStart, 0)
        XCTAssertEqual(videoClip.duration, 120)

        let overlay = project.tracks[1].clips[0]
        XCTAssertEqual(overlay.timelineStart, 0)
        XCTAssertEqual(overlay.sourceIn, 30, accuracy: 1e-9)
        XCTAssertEqual(overlay.distanceUnit, .kilometers)
        XCTAssertNotNil(overlay.layout)
        // overlay activity elapsed must equal the old sync mapping
        for t in stride(from: 0.0, through: 120.0, by: 15.0) {
            XCTAssertEqual(overlay.sourceTime(atTimelineTime: t), sync.rawFitElapsed(forVideoTime: t), accuracy: 1e-9)
        }
    }

    func testMigrationVideoLeadsActivityNegativeOffset() {
        let sync = TelemetryTimeSync(videoSyncTime: 49, fitSyncTime: 0) // offset -49 (video leads)
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .meters,
            videoAsset: videoAsset(duration: 120),
            activityAsset: activityAsset(duration: 300),
            sync: sync, layout: .default
        )
        let overlay = project.tracks[1].clips[0]
        XCTAssertEqual(overlay.timelineStart, 49, accuracy: 1e-9) // overlay starts where activity begins
        XCTAssertEqual(overlay.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(overlay.duration, 71, accuracy: 1e-9)       // 120 - 49
        XCTAssertFalse(overlay.contains(timelineTime: 40))         // before activity begins
        // mapping holds inside the clip
        for t in stride(from: 49.0, through: 120.0, by: 10.0) {
            XCTAssertEqual(overlay.sourceTime(atTimelineTime: t), sync.rawFitElapsed(forVideoTime: t), accuracy: 1e-9)
        }
    }

    func testMigrationActivityOnly() {
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            videoAsset: nil,
            activityAsset: activityAsset(duration: 300),
            sync: .identity, layout: .default
        )
        XCTAssertEqual(project.tracks.count, 1)
        XCTAssertEqual(project.tracks[0].kind, .overlay)
        let overlay = project.tracks[0].clips[0]
        XCTAssertEqual(overlay.timelineStart, 0)
        XCTAssertEqual(overlay.sourceIn, 0)
        XCTAssertEqual(overlay.duration, 300)
        XCTAssertEqual(project.duration, 300)
    }
}
