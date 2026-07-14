import XCTest
@testable import OverlayCore

final class TimelineAutoAlignmentTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func asset(
        id: String,
        kind: MediaAsset.Kind = .video,
        duration: TimeInterval,
        wallClockStart: Date?
    ) -> MediaAsset {
        MediaAsset(
            id: id,
            kind: kind,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            displayName: id,
            duration: duration,
            wallClockStart: wallClockStart
        )
    }

    private func project(assets: [MediaAsset], tracks: [TimelineTrack]) -> TimelineProject {
        TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: assets,
            tracks: tracks
        )
    }

    private func clip(
        id: String,
        assetID: String,
        start: TimeInterval,
        duration: TimeInterval,
        sourceIn: TimeInterval = 0,
        isAlignmentPending: Bool = false
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            assetID: assetID,
            timelineStart: start,
            duration: duration,
            sourceIn: sourceIn,
            isAlignmentPending: isAlignmentPending
        )
    }

    func testAlignsRelativeToPlacedReferenceClip() {
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 0, duration: 147)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(2434), in: project),
            .aligned(2434)
        )
    }

    func testReferenceAccountsForSourceInAndTimelineStart() {
        // The clip shows source time 5 at timeline 10, so timeline zero is base - 5 + 10... i.e.
        // wall clock at timeline zero = (base + 5) - 10 = base - 5.
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 10, duration: 100, sourceIn: 5)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(617), in: project),
            .aligned(622)
        )
    }

    func testEarliestPlacedClipIsTheReference() {
        let early = asset(id: "early.mov", duration: 50, wallClockStart: base)
        // A later clip whose wall clock disagrees must not win the reference role.
        let late = asset(id: "late.mov", duration: 50, wallClockStart: base.addingTimeInterval(999))
        let project = project(
            assets: [early, late],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c2", assetID: late.id, start: 60, duration: 50),
                clip(id: "c1", assetID: early.id, start: 0, duration: 50)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(300), in: project),
            .aligned(300)
        )
    }

    func testMissingWallClockOnNewAsset() {
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 0, duration: 147)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: nil, in: project),
            .missingWallClock
        )
    }

    func testNoReferenceWithoutDatedPlacedClips() {
        let empty = project(assets: [], tracks: [])
        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base, in: empty),
            .noReference
        )

        let undated = asset(id: "cam1.mov", duration: 147, wallClockStart: nil)
        let withUndatedClip = project(
            assets: [undated],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: undated.id, start: 0, duration: 147)
            ])]
        )
        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base, in: withUndatedClip),
            .noReference
        )
    }

    func testPendingClipIsNotUsedAsAlignmentReference() {
        let pending = asset(id: "pending.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [pending],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(
                    id: "pending-clip",
                    assetID: pending.id,
                    start: 0,
                    duration: 147,
                    isAlignmentPending: true
                )
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(10), in: project),
            .noReference
        )
    }

    func testCandidateBeforeTimelineZeroIsNegativeSoCallerCanShift() {
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 0, duration: 147)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(-100), in: project),
            .aligned(-100)
        )
        XCTAssertEqual(
            TimelineAutoAlignment.placement(
                forAssetWallClockStart: base.addingTimeInterval(-TimelineAutoAlignment.maximumReasonableGap - 1),
                in: project
            ),
            .unreasonable
        )
    }

    func testSlightlyNegativeCandidateClampsToZero() {
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 0, duration: 147)
            ])]
        )

        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(-0.5), in: project),
            .aligned(0)
        )
    }

    func testCandidateBeyondDayGapIsUnreasonable() {
        let reference = asset(id: "cam1.mov", duration: 147, wallClockStart: base)
        let project = project(
            assets: [reference],
            tracks: [TimelineTrack(id: "v1", kind: .video, name: "V1", clips: [
                clip(id: "c1", assetID: reference.id, start: 0, duration: 147)
            ])]
        )

        let justInside = 147 + TimelineAutoAlignment.maximumReasonableGap
        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(justInside), in: project),
            .aligned(justInside)
        )
        XCTAssertEqual(
            TimelineAutoAlignment.placement(forAssetWallClockStart: base.addingTimeInterval(justInside + 1), in: project),
            .unreasonable
        )
    }

    func testSingleSourceAlignmentActivityAfterVideo() {
        XCTAssertEqual(
            TimelineAutoAlignment.singleSourceAlignment(
                videoWallClockStart: base,
                activityWallClockStart: base.addingTimeInterval(622)
            ),
            .aligned(videoSourceTime: 622, activitySourceTime: 0)
        )
    }

    func testSingleSourceAlignmentActivityBeforeVideo() {
        XCTAssertEqual(
            TimelineAutoAlignment.singleSourceAlignment(
                videoWallClockStart: base,
                activityWallClockStart: base.addingTimeInterval(-300)
            ),
            .aligned(videoSourceTime: 0, activitySourceTime: 300)
        )
    }

    func testSingleSourceAlignmentMissingOrImplausible() {
        XCTAssertEqual(
            TimelineAutoAlignment.singleSourceAlignment(videoWallClockStart: nil, activityWallClockStart: base),
            .missingWallClock
        )
        XCTAssertEqual(
            TimelineAutoAlignment.singleSourceAlignment(videoWallClockStart: base, activityWallClockStart: nil),
            .missingWallClock
        )
        XCTAssertEqual(
            TimelineAutoAlignment.singleSourceAlignment(
                videoWallClockStart: base,
                activityWallClockStart: base.addingTimeInterval(TimelineAutoAlignment.maximumReasonableGap + 1)
            ),
            .gapTooLarge
        )
    }
}
