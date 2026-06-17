import XCTest
import OverlayCore
@testable import OverlayStudio

final class LayoutPresetStoreTests: XCTestCase {
    func testSanitizedDropsBlankNamesAndRepairsDuplicateIDsAndNames() {
        let now = Date(timeIntervalSince1970: 0)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "unused",
                    name: "  ",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                ),
                LayoutPreset(
                    id: "same",
                    name: " Race ",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                ),
                LayoutPreset(
                    id: "same",
                    name: "race",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: "same"
        )

        let sanitized = state.sanitized

        XCTAssertEqual(sanitized.presets.count, 2)
        XCTAssertEqual(sanitized.presets[0].id, "same")
        XCTAssertNotEqual(sanitized.presets[1].id, "same")
        XCTAssertFalse(sanitized.presets[1].id.isEmpty)
        XCTAssertEqual(sanitized.presets[0].name, "Race")
        XCTAssertEqual(sanitized.presets[1].name, "race 2")
        XCTAssertEqual(sanitized.defaultPresetID, "same")
    }

    func testSanitizedClearsDanglingDefaultPresetID() {
        let now = Date(timeIntervalSince1970: 0)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "preset",
                    name: "Race",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: "missing"
        )

        XCTAssertNil(state.sanitized.defaultPresetID)
    }

    func testSanitizedTrimsDefaultPresetIDBeforeMapping() {
        let now = Date(timeIntervalSince1970: 0)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: " preset ",
                    name: "Race",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: " preset "
        )

        XCTAssertEqual(state.sanitized.defaultPresetID, "preset")
    }
}
