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

    func testProjectActiveClipsUsesLastOverlappingClipPerEnabledTrackInTrackOrder() {
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            tracks: [
                TimelineTrack(id: "o1", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "o1-a", assetID: "a", timelineStart: 0, duration: 10),
                    TimelineClip(id: "o1-b", assetID: "b", timelineStart: 5, duration: 10)
                ]),
                TimelineTrack(id: "disabled", kind: .overlay, name: "O2", isEnabled: false, clips: [
                    TimelineClip(id: "disabled-clip", assetID: "c", timelineStart: 0, duration: 10)
                ]),
                TimelineTrack(id: "o3", kind: .overlay, name: "O3", clips: [
                    TimelineClip(id: "o3-a", assetID: "d", timelineStart: 0, duration: 10)
                ])
            ]
        )

        XCTAssertEqual(
            project.activeClips(kind: .overlay, atTimelineTime: 7).map(\.id),
            ["o1-b", "o3-a"]
        )
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

    func testProjectSnapsTimelineTimeToNearbyClipEdges() {
        let project = TimelineProject(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            tracks: [
                TimelineTrack(id: "v", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "a", assetID: "vid", timelineStart: 10, duration: 20),
                    TimelineClip(id: "b", assetID: "vid", timelineStart: 45, duration: 10)
                ])
            ]
        )

        XCTAssertEqual(project.snappedTimelineTime(29.8, threshold: 0.25), 30)
        XCTAssertEqual(project.snappedTimelineTime(0.1, threshold: 0.25), 0)
        XCTAssertEqual(project.snappedTimelineTime(44.6, threshold: 0.25), 44.6)
        XCTAssertEqual(project.snappedTimelineTime(45.1, threshold: 0.25, excludingClipID: "b"), 45.1)
        XCTAssertEqual(
            project.snappedTimelineTime(
                39.8,
                threshold: 0.25,
                excludingClipID: "a",
                additionalCandidates: [40]
            ),
            40
        )
    }

    func testVideoExportPreflightAllowsSparseClipsAndEmptyVideoRanges() {
        let project = exportProject(
            videoClips: [
                TimelineClip(id: "video-a", assetID: "video-a", timelineStart: 0, duration: 1),
                TimelineClip(id: "video-b", assetID: "video-b", timelineStart: 1.5, duration: 1)
            ]
        )

        XCTAssertNil(
            project.firstExportValidationIssue(
                mode: .video,
                timelineStart: 0,
                duration: 3,
                availableTelemetryAssetIDs: ["activity"]
            )
        )

        XCTAssertNil(
            exportProject(videoClips: []).firstExportValidationIssue(
                mode: .video,
                timelineStart: 0,
                duration: 3,
                availableTelemetryAssetIDs: ["activity"]
            )
        )
    }

    func testVideoExportResolvesUpperTrackCoverageAndRestoresLowerSourceTime() throws {
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [
                videoAsset(id: "bottom", duration: 10),
                videoAsset(id: "top", duration: 10),
                activityAsset(id: "activity", duration: 10)
            ],
            tracks: [
                TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "bottom-clip", assetID: "bottom", timelineStart: 0, duration: 10)
                ]),
                TimelineTrack(id: "v2", kind: .video, name: "V2", clips: [
                    TimelineClip(id: "top-clip", assetID: "top", timelineStart: 3, duration: 4, sourceIn: 1)
                ]),
                TimelineTrack(id: "o1", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "activity-clip", assetID: "activity", timelineStart: 0, duration: 10)
                ])
            ]
        )

        let visible = try project.validatedVideoClipsForExport(timelineStart: 0, duration: 10)
        XCTAssertEqual(visible.map(\.assetID), ["bottom", "top", "bottom"])
        XCTAssertEqual(visible.map(\.timelineStart), [0, 3, 7])
        XCTAssertEqual(visible.map(\.duration), [3, 4, 3])
        XCTAssertEqual(visible.map(\.sourceIn), [0, 1, 7])
        XCTAssertEqual(visible.map(\.id), ["bottom-clip", "top-clip", "bottom-clip.visible.1"])

        XCTAssertNil(
            project.firstExportValidationIssue(
                mode: .video,
                timelineStart: 0,
                duration: 10,
                availableTelemetryAssetIDs: ["activity"]
            )
        )
    }

    // MARK: Codable

    func testProjectCodableRoundTrip() throws {
        let original = TimelineProject.migratingSingleSource(
            outputWidth: 1920, outputHeight: 1080, framesPerSecond: 30, distanceUnit: .kilometers,
            videoAsset: videoAsset(duration: 120),
            activityAsset: activityAsset(duration: 300),
            sync: TelemetryTimeSync(videoSyncTime: 10, fitSyncTime: 40),
            layout: .default
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testProjectDecodesLegacyJSONWithoutSourceMatchPoint() throws {
        let data = Data("""
        {
          "outputWidth": 1920,
          "outputHeight": 1080,
          "framesPerSecond": 30,
          "distanceUnit": "km",
          "assets": [],
          "tracks": []
        }
        """.utf8)

        let project = try JSONDecoder().decode(TimelineProject.self, from: data)

        XCTAssertNil(project.sourceMatchPoint)
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
        XCTAssertEqual(videoClip.timelineStart, 30)
        XCTAssertEqual(videoClip.duration, 120)

        let overlay = project.tracks[1].clips[0]
        XCTAssertEqual(overlay.timelineStart, 0)
        XCTAssertEqual(overlay.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(overlay.duration, 300, accuracy: 1e-9)      // synchronization keeps the full activity
        XCTAssertEqual(project.duration, 300)                      // placement, not trimming, expresses the offset
        XCTAssertEqual(overlay.distanceUnit, .kilometers)
        XCTAssertNotNil(overlay.layout)
        XCTAssertEqual(
            project.sourceMatchPoint,
            TimelineSourceMatchPoint(
                videoAssetID: videoClip.assetID,
                activityAssetID: overlay.assetID,
                videoSourceTime: 10,
                activitySourceTime: 40
            )
        )
        XCTAssertEqual(
            videoClip.timelineStart + sync.videoSyncTime,
            overlay.timelineStart + sync.fitSyncTime,
            accuracy: 1e-9
        )
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
        XCTAssertEqual(overlay.duration, 300, accuracy: 1e-9)      // full activity length (outlasts the video)
        XCTAssertEqual(project.duration, 349, accuracy: 1e-9)      // 49 + 300
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
        XCTAssertNil(project.sourceMatchPoint)
    }

    func testAlignMatchPointUsesRelativeTimelinePositionsAndPreservesLeadingBlank() throws {
        var project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [videoAsset(duration: 120), activityAsset(duration: 300)],
            tracks: [
                TimelineTrack(
                    id: "video",
                    kind: .video,
                    name: "V1",
                    clips: [TimelineClip(id: "video-clip", assetID: "video", timelineStart: 50, duration: 120)]
                ),
                TimelineTrack(
                    id: "overlay",
                    kind: .overlay,
                    name: "O1",
                    clips: [TimelineClip(id: "activity-clip", assetID: "activity", timelineStart: 80, duration: 300)]
                )
            ]
        )

        XCTAssertTrue(project.alignMatchPoint(
            anchorClipID: "video-clip",
            anchorSourceTime: 10,
            movingClipID: "activity-clip",
            movingSourceTime: 40
        ))

        let video = try XCTUnwrap(project.tracks[0].clips.first)
        let activity = try XCTUnwrap(project.tracks[1].clips.first)
        XCTAssertEqual(video.timelineStart, 50, accuracy: 1e-9)
        XCTAssertEqual(activity.timelineStart, 20, accuracy: 1e-9)
        XCTAssertEqual(
            video.timelineTime(forSourceTime: 10),
            activity.timelineTime(forSourceTime: 40),
            accuracy: 1e-9
        )
        XCTAssertTrue(project.activeClips(kind: .video, atTimelineTime: 0).isEmpty)
        XCTAssertTrue(project.activeClips(kind: .overlay, atTimelineTime: 0).isEmpty)
    }

    // MARK: split / delete / ripple delete

    private func editingProject() -> TimelineProject {
        TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [
                videoAsset(id: "video", duration: 200),
                activityAsset(id: "activity", duration: 200)
            ],
            tracks: [
                TimelineTrack(id: "video-track", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "video-a", assetID: "video", timelineStart: 0, duration: 10, sourceIn: 2),
                    TimelineClip(id: "video-b", assetID: "video", timelineStart: 10, duration: 10, sourceIn: 40),
                    TimelineClip(id: "video-c", assetID: "video", timelineStart: 25, duration: 10, sourceIn: 80)
                ]),
                TimelineTrack(id: "overlay-track", kind: .overlay, name: "O1", clips: [
                    TimelineClip(
                        id: "overlay-a",
                        assetID: "activity",
                        timelineStart: 5,
                        duration: 25,
                        sourceIn: 3,
                        layout: .default,
                        distanceUnit: .meters
                    )
                ]),
                TimelineTrack(id: "locked-track", kind: .overlay, name: "O2", isLocked: true, clips: [
                    TimelineClip(id: "locked-clip", assetID: "activity", timelineStart: 0, duration: 30)
                ])
            ]
        )
    }

    func testSplitClipsCutsEveryUnlockedClipUnderTime() throws {
        var project = editingProject()
        var nextID = 0
        let count = project.splitClips(atTimelineTime: 15) {
            nextID += 1
            return "new-\(nextID)"
        }

        XCTAssertEqual(count, 2) // video-b and overlay-a; the locked clip stays whole

        let videoClips = project.tracks[0].clips
        XCTAssertEqual(videoClips.map(\.id), ["video-a", "video-b", "new-1", "video-c"])
        let left = videoClips[1]
        let right = videoClips[2]
        XCTAssertEqual(left.timelineStart, 10, accuracy: 1e-9)
        XCTAssertEqual(left.duration, 5, accuracy: 1e-9)
        XCTAssertEqual(left.sourceIn, 40, accuracy: 1e-9)
        XCTAssertEqual(right.timelineStart, 15, accuracy: 1e-9)
        XCTAssertEqual(right.duration, 5, accuracy: 1e-9)
        // Source content is continuous across the cut.
        XCTAssertEqual(right.sourceIn, 45, accuracy: 1e-9)
        XCTAssertEqual(right.assetID, left.assetID)

        let overlayClips = project.tracks[1].clips
        XCTAssertEqual(overlayClips.count, 2)
        XCTAssertEqual(overlayClips[0].id, "overlay-a")
        XCTAssertEqual(overlayClips[1].id, "new-2")
        XCTAssertEqual(overlayClips[1].sourceIn, 13, accuracy: 1e-9)
        // Per-clip layout/unit carry over to both pieces.
        XCTAssertEqual(overlayClips[1].layout, overlayClips[0].layout)
        XCTAssertEqual(overlayClips[1].distanceUnit, .meters)

        XCTAssertEqual(project.tracks[2].clips.map(\.id), ["locked-clip"])
    }

    func testSplitClipsCutsOnlyTheSelectedTrack() {
        var project = editingProject()
        XCTAssertEqual(
            project.splittableClipIDs(atTimelineTime: 15, trackIDs: ["video-track"]),
            ["video-b"]
        )

        let count = project.splitClips(atTimelineTime: 15, trackIDs: ["video-track"]) {
            "video-b-right"
        }

        XCTAssertEqual(count, 1)
        XCTAssertEqual(
            project.tracks[0].clips.map(\.id),
            ["video-a", "video-b", "video-b-right", "video-c"]
        )
        XCTAssertEqual(project.tracks[1].clips.map(\.id), ["overlay-a"])
        XCTAssertEqual(project.tracks[2].clips.map(\.id), ["locked-clip"])
        XCTAssertTrue(
            project.splittableClipIDs(atTimelineTime: 15, trackIDs: ["locked-track"]).isEmpty
        )

        var multipleTracks = editingProject()
        XCTAssertEqual(
            multipleTracks.splitClips(
                atTimelineTime: 15,
                trackIDs: ["video-track", "overlay-track"]
            ),
            2
        )
    }

    func testSplitClipsSkipsCutsTooCloseToClipEdges() {
        var project = editingProject()
        // 10.05 is within the 0.1s minimum piece of video-b's left edge; overlay-a is unaffected
        // at that time only if the cut also violates its edges — it does not, so it still splits.
        XCTAssertEqual(Set(project.splittableClipIDs(atTimelineTime: 10.05)), ["overlay-a"])
        XCTAssertEqual(project.splitClips(atTimelineTime: 10.05), 1)
        XCTAssertEqual(project.tracks[0].clips.count, 3)
        XCTAssertEqual(project.tracks[1].clips.count, 2)

        var untouched = editingProject()
        XCTAssertEqual(untouched.splitClips(atTimelineTime: 40), 0)
        XCTAssertEqual(untouched, editingProject())
    }

    func testRemoveClipLeavesGapAndKeepsOtherClipsInPlace() {
        var project = editingProject()
        XCTAssertTrue(project.removeClip(id: "video-b"))

        XCTAssertEqual(project.tracks[0].clips.map(\.id), ["video-a", "video-c"])
        XCTAssertEqual(project.tracks[0].clips[1].timelineStart, 25, accuracy: 1e-9)
        XCTAssertEqual(project.tracks[1].clips[0].timelineStart, 5, accuracy: 1e-9)

        XCTAssertFalse(project.removeClip(id: "locked-clip"))
        XCTAssertFalse(project.removeClip(id: "missing"))
    }

    func testRippleRemoveClipClosesRangeAcrossUnlockedTracks() throws {
        var project = editingProject()
        var nextID = 0
        XCTAssertTrue(project.rippleRemoveClip(id: "video-b") {
            nextID += 1
            return "seam-\(nextID)"
        })

        // Video track: the 10s range [10, 20) closes; the later clip shifts left.
        let videoClips = project.tracks[0].clips
        XCTAssertEqual(videoClips.map(\.id), ["video-a", "video-c"])
        XCTAssertEqual(videoClips[1].timelineStart, 15, accuracy: 1e-9)
        XCTAssertEqual(videoClips[1].sourceIn, 80, accuracy: 1e-9)

        // Overlay clip [5, 30) spans the range: head keeps [5, 10), the tail continues at the
        // seam with the matching source content removed, so video and data stay in sync.
        let overlayClips = project.tracks[1].clips
        XCTAssertEqual(overlayClips.map(\.id), ["overlay-a", "seam-1"])
        XCTAssertEqual(overlayClips[0].timelineStart, 5, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[0].duration, 5, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[0].sourceIn, 3, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[1].timelineStart, 10, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[1].duration, 10, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[1].sourceIn, 18, accuracy: 1e-9)
        XCTAssertEqual(overlayClips[1].layout, overlayClips[0].layout)

        // Locked tracks do not ripple.
        XCTAssertEqual(project.tracks[2].clips[0].timelineStart, 0, accuracy: 1e-9)
        XCTAssertEqual(project.tracks[2].clips[0].duration, 30, accuracy: 1e-9)
    }

    func testRemoveTimeRangeTrimsPartialOverlapsAndDropsCoveredClips() {
        var project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [activityAsset(id: "activity", duration: 200)],
            tracks: [
                TimelineTrack(id: "o1", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "head", assetID: "activity", timelineStart: 0, duration: 15, sourceIn: 1),
                    TimelineClip(id: "inside", assetID: "activity", timelineStart: 16, duration: 2),
                    TimelineClip(id: "tail", assetID: "activity", timelineStart: 18, duration: 10, sourceIn: 50)
                ])
            ]
        )

        project.removeTimeRange(from: 10, to: 20)

        let clips = project.tracks[0].clips
        XCTAssertEqual(clips.map(\.id), ["head", "tail"])
        // "head" overlaps the range start: it keeps only [0, 10).
        XCTAssertEqual(clips[0].duration, 10, accuracy: 1e-9)
        XCTAssertEqual(clips[0].sourceIn, 1, accuracy: 1e-9)
        // "inside" sat entirely inside the removed range and is gone.
        // "tail" overlaps the range end: its first 2 seconds are cut and it moves to the seam.
        XCTAssertEqual(clips[1].timelineStart, 10, accuracy: 1e-9)
        XCTAssertEqual(clips[1].duration, 8, accuracy: 1e-9)
        XCTAssertEqual(clips[1].sourceIn, 52, accuracy: 1e-9)
    }

    // MARK: overlap prevention

    private func occupiedTrack() -> TimelineTrack {
        TimelineTrack(id: "t", kind: .video, name: "V1", clips: [
            TimelineClip(id: "a", assetID: "x", timelineStart: 0, duration: 10),
            TimelineClip(id: "b", assetID: "x", timelineStart: 20, duration: 10),
            TimelineClip(id: "m", assetID: "x", timelineStart: 40, duration: 5)
        ])
    }

    func testNonOverlappingStartClampsIntoNearestFittingGap() {
        let track = occupiedTrack()

        // Fits at the proposed position: unchanged.
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "m", duration: 5, proposedStart: 12), 12, accuracy: 1e-9)
        // Proposed inside clip "b": clamps to the nearest edge of a fitting gap.
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "m", duration: 5, proposedStart: 21), 15, accuracy: 1e-9)
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "m", duration: 5, proposedStart: 28), 30, accuracy: 1e-9)
        // Too long for the middle gap: jumps to the open tail.
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "m", duration: 12, proposedStart: 12), 30, accuracy: 1e-9)
        // The moved clip itself is excluded from the occupancy check.
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "b", duration: 10, proposedStart: 20), 20, accuracy: 1e-9)
        // Clips may touch exactly.
        XCTAssertEqual(track.nonOverlappingStart(forClipID: "m", duration: 10, proposedStart: 10), 10, accuracy: 1e-9)
    }

    func testNeighborBoundsAndMaximumDurationRespectAdjacentClips() {
        let track = occupiedTrack()

        let bounds = track.neighborBounds(aroundClipID: "b")
        XCTAssertEqual(bounds.lower, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(bounds.upper), 40, accuracy: 1e-9)

        let tailBounds = track.neighborBounds(aroundClipID: "m")
        XCTAssertEqual(tailBounds.lower, 30, accuracy: 1e-9)
        XCTAssertNil(tailBounds.upper)

        // For "b" the next other clip is "m" at 40.
        XCTAssertEqual(
            try XCTUnwrap(track.maximumNonOverlappingDuration(forClipID: "b", startingAt: 12)),
            28,
            accuracy: 1e-9
        )
        XCTAssertNil(track.maximumNonOverlappingDuration(forClipID: "m", startingAt: 50))
    }

    private func exportProject(videoClips: [TimelineClip]) -> TimelineProject {
        TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [
                videoAsset(id: "video-a", duration: 3),
                videoAsset(id: "video-b", duration: 3),
                activityAsset(id: "activity", duration: 3)
            ],
            tracks: [
                TimelineTrack(id: "video", kind: .video, name: "V1", clips: videoClips),
                TimelineTrack(id: "overlay", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "activity-clip", assetID: "activity", timelineStart: 0, duration: 3)
                ])
            ]
        )
    }
}
