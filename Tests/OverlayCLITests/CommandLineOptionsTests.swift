import XCTest
import OverlayCore
@testable import overlay

final class CommandLineOptionsTests: XCTestCase {
    func testVideoArgumentIsOptionalForFITOnlyExport() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--width", "1920",
            "--height", "1080"
        ])

        XCTAssertNil(options.videoURL)
        XCTAssertEqual(options.width, 1920)
        XCTAssertEqual(options.height, 1080)
        XCTAssertEqual(options.exportMode, .overlay)
        XCTAssertEqual(options.codec, .hevcAlpha)
    }

    func testCompositedVideoExportAllowsBlackCanvasWithoutSourceVideo() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--fit", "activity.fit",
            "--output", "video.mov",
            "--export-mode", "video"
        ])

        XCTAssertNil(options.videoURL)
        XCTAssertEqual(options.exportMode, .video)
        XCTAssertEqual(options.codec, .hevc)
    }

    func testCompositedVideoExportDefaultsToPlainHEVC() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "video.mov",
            "--export-mode", "video"
        ])

        XCTAssertEqual(options.exportMode, .video)
        XCTAssertEqual(options.codec, .hevc)
    }

    func testAlphaCodecCannotBeUsedForCompositedVideoExport() {
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "video.mov",
            "--export-mode", "video",
            "--codec", "hevc-alpha"
        ])) { error in
            guard case CLIError.conflictingArguments(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("hevc-alpha"))
            XCTAssertTrue(message.contains("video"))
        }
    }

    func testPlainVideoCodecCannotBeUsedForOverlayExport() {
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: [
            "overlay",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--codec", "hevc"
        ])) { error in
            guard case CLIError.conflictingArguments(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("hevc"))
            XCTAssertTrue(message.contains("overlay"))
        }
    }

    func testBitrateArgumentUsesKbpsAtGuiMaximum() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--bitrate", "1000000"
        ])

        XCTAssertEqual(options.averageBitRate, 1_000_000_000)
    }

    func testBitrateArgumentKeepsLegacyBpsAboveGuiMaximum() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--bitrate", "12000000"
        ])

        XCTAssertEqual(options.averageBitRate, 12_000_000)
    }

    func testLayoutPresetArgumentStoresReference() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--layout-preset", "Race Layout"
        ])

        XCTAssertEqual(options.layoutPresetReference, "Race Layout")
    }

    func testActivityTrimArgumentsStoreOriginalActivityRange() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--activity-trim-start", "120.5",
            "--activity-trim-end", "420.25"
        ])

        XCTAssertEqual(options.activityTrim.startSeconds, 120.5, accuracy: 0.001)
        XCTAssertEqual(options.activityTrim.endSeconds ?? -1, 420.25, accuracy: 0.001)
    }

    func testActivityTrimEndMustNotBeBeforeStart() {
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: [
            "overlay",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--activity-trim-start", "60",
            "--activity-trim-end", "30"
        ])) { error in
            guard case CLIError.conflictingArguments(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("--activity-trim-end"))
        }
    }

    func testTimelineProjectArgumentDoesNotRequireFITOrVideo() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--timeline-project", "project.dlsproj",
            "--output", "timeline.mov",
            "--export-mode", "video"
        ])

        XCTAssertEqual(options.timelineProjectURL?.lastPathComponent, "project.dlsproj")
        XCTAssertNil(options.fitURL)
        XCTAssertNil(options.videoURL)
        XCTAssertEqual(options.exportMode, .video)
        XCTAssertEqual(options.codec, .hevc)
    }

    func testTimelineProjectCannotBeCombinedWithSingleSourceInputs() {
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: [
            "overlay",
            "--timeline-project", "project.dlsproj",
            "--fit", "activity.fit",
            "--output", "timeline.mov"
        ])) { error in
            guard case CLIError.conflictingArguments(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("--timeline-project"))
            XCTAssertTrue(message.contains("--fit"))
        }
    }

    func testLoadTimelineProjectFromJSON() throws {
        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "fit",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity.fit"),
                    displayName: "activity.fit",
                    duration: 60
                )
            ],
            tracks: [
                TimelineTrack(id: "o1", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "c1", assetID: "fit", timelineStart: 0, duration: 60)
                ])
            ]
        )
        let fileURL = temporaryPresetURL()
        try JSONEncoder().encode(project).write(to: fileURL)

        let loaded = try loadTimelineProject(from: fileURL)

        XCTAssertEqual(loaded, project)
    }

    func testTimelineProjectCLIAllowsVideoGapAndUpperTrackOverlapDuringSharedPreflight() throws {
        let activityURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("datalayer-cli-preflight-\(UUID().uuidString)")
            .appendingPathExtension("gpx")
        let projectURL = temporaryPresetURL()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("datalayer-cli-preflight-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: activityURL)
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="DataLayer Studio" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="35.0" lon="139.0"><time>2026-07-10T00:00:00Z</time></trkpt>
            <trkpt lat="35.0001" lon="139.0001"><time>2026-07-10T00:00:03Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
        try Data(gpx.utf8).write(to: activityURL)

        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(id: "video-a", kind: .video, url: URL(fileURLWithPath: "/tmp/a.mov"), displayName: "a.mov", duration: 2),
                MediaAsset(id: "video-b", kind: .video, url: URL(fileURLWithPath: "/tmp/b.mov"), displayName: "b.mov", duration: 2),
                MediaAsset(id: "activity", kind: .activity, url: activityURL, displayName: activityURL.lastPathComponent, duration: 3)
            ],
            tracks: [
                TimelineTrack(id: "video-a", kind: .video, name: "V1", clips: [
                    TimelineClip(id: "video-a", assetID: "video-a", timelineStart: 0, duration: 2)
                ]),
                TimelineTrack(id: "video-b", kind: .video, name: "V2", clips: [
                    TimelineClip(id: "video-b", assetID: "video-b", timelineStart: 0.5, duration: 1)
                ]),
                TimelineTrack(id: "overlay", kind: .overlay, name: "O1", clips: [
                    TimelineClip(id: "activity", assetID: "activity", timelineStart: 0, duration: 2.5)
                ])
            ]
        )
        try JSONEncoder().encode(project).write(to: projectURL)
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--timeline-project", projectURL.path,
            "--output", outputURL.path,
            "--export-mode", "video",
            "--inspect"
        ])

        XCTAssertNoThrow(try renderTimelineProject(options: options, projectURL: projectURL))
    }

    func testDurationArgumentIsNoLongerSupported() {
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--duration", "60"
        ])) { error in
            guard case CLIError.unknownArgument("--duration") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testResolveLayoutPresetMatchesNameCaseInsensitively() throws {
        let now = Date(timeIntervalSince1970: 0)
        var layout = OverlayLayout.default
        layout.speed = OverlayComponentFrame(x: 0.42, y: 0.11, scale: 1.2)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "race-layout-id",
                    name: "Race Layout",
                    layout: layout,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: nil
        )

        let resolved = try resolveOverlayLayout(
            presetReference: "race layout",
            loadPresetState: { state }
        )

        XCTAssertEqual(resolved.presetName, "Race Layout")
        XCTAssertEqual(resolved.layout.component(.speed).x, 0.42, accuracy: 0.0001)
        XCTAssertEqual(resolved.layout.component(.speed).scale, 1.2, accuracy: 0.0001)
    }

    func testResolveLayoutPresetMatchesIDBeforeName() throws {
        let now = Date(timeIntervalSince1970: 0)
        var layoutByID = OverlayLayout.default
        layoutByID.speed = OverlayComponentFrame(x: 0.33, y: 0.1, scale: 1)
        var layoutByName = OverlayLayout.default
        layoutByName.speed = OverlayComponentFrame(x: 0.66, y: 0.1, scale: 1)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "shared",
                    name: "ID Match",
                    layout: layoutByID,
                    createdAt: now,
                    updatedAt: now
                ),
                LayoutPreset(
                    id: "other",
                    name: "shared",
                    layout: layoutByName,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: nil
        )

        let resolved = try resolveOverlayLayout(
            presetReference: "shared",
            loadPresetState: { state }
        )

        XCTAssertEqual(resolved.presetName, "ID Match")
        XCTAssertEqual(resolved.layout.component(.speed).x, 0.33, accuracy: 0.0001)
    }

    func testResolveLayoutPresetThrowsWhenMissing() {
        XCTAssertThrowsError(try resolveOverlayLayout(
            presetReference: "missing",
            loadPresetState: { .empty }
        )) { error in
            guard case CLIError.layoutPresetNotFound("missing") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testResolveLayoutPresetLoadsDefaultPresetFromExportedJSONFile() throws {
        let now = Date(timeIntervalSince1970: 0)
        var firstLayout = OverlayLayout.default
        firstLayout.speed = OverlayComponentFrame(x: 0.2, y: 0.1, scale: 1)
        var defaultLayout = OverlayLayout.default
        defaultLayout.speed = OverlayComponentFrame(x: 0.7, y: 0.1, scale: 1.4)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "first",
                    name: "First",
                    layout: firstLayout,
                    createdAt: now,
                    updatedAt: now
                ),
                LayoutPreset(
                    id: "default",
                    name: "Default Export",
                    layout: defaultLayout,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: "default"
        )
        let fileURL = try writePresetFixture(state)

        let resolved = try resolveOverlayLayout(
            presetReference: fileURL.path,
            loadPresetState: { .empty }
        )

        XCTAssertEqual(resolved.presetName, "Default Export")
        XCTAssertEqual(resolved.layout.component(.speed).x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(resolved.layout.component(.speed).scale, 1.4, accuracy: 0.0001)
    }

    func testResolveLayoutPresetLoadsFirstPresetWhenExportedJSONHasNoDefault() throws {
        let now = Date(timeIntervalSince1970: 0)
        var firstLayout = OverlayLayout.default
        firstLayout.speed = OverlayComponentFrame(x: 0.23, y: 0.1, scale: 1)
        var secondLayout = OverlayLayout.default
        secondLayout.speed = OverlayComponentFrame(x: 0.82, y: 0.1, scale: 1)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "first",
                    name: "First Export",
                    layout: firstLayout,
                    createdAt: now,
                    updatedAt: now
                ),
                LayoutPreset(
                    id: "second",
                    name: "Second Export",
                    layout: secondLayout,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: nil
        )
        let fileURL = try writePresetFixture(state)

        let resolved = try resolveOverlayLayout(
            presetReference: fileURL.path,
            loadPresetState: { .empty }
        )

        XCTAssertEqual(resolved.presetName, "First Export")
        XCTAssertEqual(resolved.layout.component(.speed).x, 0.23, accuracy: 0.0001)
    }

    func testResolveLayoutPresetLoadsSinglePresetJSONFile() throws {
        let now = Date(timeIntervalSince1970: 0)
        var layout = OverlayLayout.default
        layout.speed = OverlayComponentFrame(x: 0.58, y: 0.1, scale: 1.3)
        let preset = LayoutPreset(
            id: "single",
            name: "Single Export",
            layout: layout,
            createdAt: now,
            updatedAt: now
        )
        let fileURL = try writePresetFixture(preset)

        let resolved = try resolveOverlayLayout(
            presetReference: fileURL.path,
            loadPresetState: { .empty }
        )

        XCTAssertEqual(resolved.presetName, "Single Export")
        XCTAssertEqual(resolved.layout.component(.speed).x, 0.58, accuracy: 0.0001)
        XCTAssertEqual(resolved.layout.component(.speed).scale, 1.3, accuracy: 0.0001)
    }

    func testResolveLayoutPresetThrowsWhenJSONFileHasNoPreset() throws {
        let fileURL = temporaryPresetURL()
        try #"{"presets":[]}"#.data(using: .utf8)!.write(to: fileURL)

        XCTAssertThrowsError(try resolveOverlayLayout(
            presetReference: fileURL.path,
            loadPresetState: { .empty }
        )) { error in
            guard case CLIError.layoutPresetFileInvalid(fileURL.path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func writePresetFixture<T: Encodable>(_ value: T) throws -> URL {
        let fileURL = temporaryPresetURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: fileURL)
        return fileURL
    }

    private func temporaryPresetURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("datalayer-cli-layout-preset-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }
}
