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
