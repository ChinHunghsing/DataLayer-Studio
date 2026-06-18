import XCTest
import OverlayCore
@testable import overlay

final class CommandLineOptionsTests: XCTestCase {
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
}
