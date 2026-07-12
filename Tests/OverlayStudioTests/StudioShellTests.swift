import CoreGraphics
import XCTest
@testable import OverlayCore
@testable import OverlayStudio

@MainActor
final class StudioShellTests: XCTestCase {
    func testExternalFileClassifierDistinguishesSupportedTypes() {
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/project.dlsproj")), .timelineProject)
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/preset.dlspreset")), .layoutPreset)
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/legacy.json")), .legacyJSON)
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/movie.mov")), .video)
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/activity.fit")), .activity)
        XCTAssertEqual(StudioExternalFileKind.classify(URL(fileURLWithPath: "/tmp/file.txt")), .unsupported)
    }

    func testSourceContinuationPromptOffersTheMissingCounterpart() {
        XCTAssertEqual(
            SourceContinuationPrompt.forSources(hasVideo: true, hasActivity: false),
            .activityAfterVideo
        )
        XCTAssertEqual(
            SourceContinuationPrompt.forSources(hasVideo: false, hasActivity: true),
            .videoAfterActivity
        )
        XCTAssertNil(SourceContinuationPrompt.forSources(hasVideo: true, hasActivity: true))
        XCTAssertNil(SourceContinuationPrompt.forSources(hasVideo: false, hasActivity: false))
    }

    func testSelectingLibraryAssetDoesNotChangeActiveVideo() {
        let model = StudioModel()
        let firstURL = URL(fileURLWithPath: "/tmp/first.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/second.mov")
        model.upsertVideoAsset(url: firstURL, metadata: metadata())
        model.upsertVideoAsset(url: secondURL, metadata: metadata())
        model.videoURL = firstURL

        model.selectMediaAsset(id: secondURL.path)

        XCTAssertEqual(model.selectedMediaAssetID, secondURL.path)
        XCTAssertEqual(model.activeVideoAssetID, firstURL.path)
        XCTAssertEqual(model.videoURL, firstURL)
        XCTAssertNil(model.selectedElementID)
    }

    func testAddingComponentAtNormalizedPositionUsesRequestedLocation() throws {
        let model = StudioModel()

        model.addElement(kind: .power, atNormalizedPosition: CGPoint(x: 0.42, y: 0.31))

        let element = try XCTUnwrap(model.layout.elements.last)
        XCTAssertEqual(element.kind, .power)
        XCTAssertEqual(element.frame.x, 0.42, accuracy: 0.000_1)
        XCTAssertEqual(element.frame.y, 0.31, accuracy: 0.000_1)
        XCTAssertEqual(model.selectedElementID, element.id)
    }

    func testAddingComponentCenteredPlacesItsBoundsAtCanvasCenter() throws {
        let model = StudioModel()

        model.addElementCentered(kind: .power)

        let element = try XCTUnwrap(model.layout.elements.last)
        let baseSize = ComponentBaseSize.size(for: .power)
        XCTAssertEqual(element.frame.x + Double(baseSize.width) / Double(model.outputWidth) / 2, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(element.frame.y + Double(baseSize.height) / Double(model.outputHeight) / 2, 0.5, accuracy: 0.000_1)
    }

    func testAddingComponentUpdatesActiveCustomTimelineOverlayLayout() throws {
        let model = StudioModel()
        let asset = MediaAsset(
            id: "activity",
            kind: .activity,
            url: URL(fileURLWithPath: "/tmp/activity.fit"),
            displayName: "activity.fit",
            duration: 30
        )
        let clip = TimelineClip(
            id: "overlay",
            assetID: asset.id,
            timelineStart: 0,
            duration: 30,
            layout: OverlayLayout(elements: [.defaultElement(kind: .speed)])
        )
        model.applyTimelineProject(TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [asset],
            tracks: [TimelineTrack(id: "O1", kind: .overlay, name: "O1", clips: [clip])]
        ), loadAssets: false)

        model.addElement(kind: .power, atNormalizedPosition: CGPoint(x: 0.42, y: 0.31))

        let updatedClip = try XCTUnwrap(model.timeline.tracks[0].clips.first)
        let added = try XCTUnwrap(updatedClip.layout?.elements.last)
        XCTAssertEqual(added.kind, .power)
        XCTAssertEqual(added.frame.x, 0.42, accuracy: 0.000_1)
        XCTAssertEqual(added.frame.y, 0.31, accuracy: 0.000_1)

        model.updateElement(added.id) { $0.frame.scale = 1.5 }
        XCTAssertEqual(model.timeline.tracks[0].clips[0].layout?.elements.last?.frame.scale, 1.5)
    }

    func testWorkspaceWidthsPreserveMinimumCanvasAtMinimumWindowSize() {
        let widths = StudioWorkspacePaneWidths.resolve(
            totalWidth: 1_100,
            requestedLibrary: 420,
            requestedInspector: 480,
            showsLibrary: true,
            showsInspector: true
        )

        XCTAssertGreaterThanOrEqual(widths.library, 260)
        XCTAssertGreaterThanOrEqual(widths.inspector, 320)
        XCTAssertLessThanOrEqual(widths.library + widths.inspector + 14 + 420, 1_100.001)
    }

    func testTimelineHeightMigratesOnlyThePreviousDefault() {
        XCTAssertEqual(StudioWorkspaceDefaults.migratedTimelineHeight(240), 300)
        XCTAssertEqual(StudioWorkspaceDefaults.migratedTimelineHeight(360), 360)
    }

    func testNewProjectWithUserTemplateUsesUnsavedConfirmation() throws {
        let model = StudioModel()
        let now = Date()
        let templateLayout = OverlayLayout(elements: [
            OverlayElement.defaultElement(kind: .power, id: "template-power")
        ])
        model.layoutPresets = [LayoutPreset(
            id: "training",
            name: "Training",
            layout: templateLayout,
            createdAt: now,
            updatedAt: now
        )]
        model.setOutputWidth(1280)
        let initialRevision = model.studioSessionRevision

        XCTAssertEqual(model.requestNewTimelineProject(layoutPresetID: "training"), .accepted)
        XCTAssertEqual(
            model.pendingTimelineAction,
            .newTimelineProject(layoutPresetID: "training", mediaURLs: [])
        )

        model.confirmPendingTimelineAction()

        XCTAssertEqual(model.outputWidth, 1920)
        XCTAssertEqual(model.layout.elements.map(\.kind), [.power])
        XCTAssertNil(model.currentTimelineProjectURL)
        XCTAssertEqual(model.studioSessionRevision, initialRevision + 1)
        XCTAssertFalse(model.hasUnsavedTimelineChanges)
    }

    func testNewProjectWithoutExplicitTemplateUsesDefaultUserTemplate() {
        let model = StudioModel()
        let templateLayout = OverlayLayout(elements: [
            OverlayElement.defaultElement(kind: .power, id: "default-template-power")
        ])
        model.layoutPresets = [LayoutPreset(
            id: "default-training",
            name: "Default Training",
            layout: templateLayout,
            createdAt: Date(),
            updatedAt: Date()
        )]
        model.defaultLayoutPresetID = "default-training"

        XCTAssertEqual(model.requestNewTimelineProject(), .accepted)

        XCTAssertEqual(model.layout, templateLayout.sanitized)
    }

    private func metadata() -> VideoMetadata {
        VideoMetadata(
            size: CGSize(width: 1920, height: 1080),
            duration: 30,
            framesPerSecond: 30,
            bitRateBitsPerSecond: 0
        )
    }
}
