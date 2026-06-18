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

    func testLoadSharedAppStateReadsSavedAppDomainPresets() throws {
        let suiteName = "run.libo.datalayer-studio.layout-preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appDomain = "\(suiteName).current"

        let now = Date(timeIntervalSince1970: 0)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "saved",
                    name: "Saved Layout",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: "saved"
        )
        let data = try JSONEncoder().encode(state)
        defaults.setPersistentDomain(
            [LayoutPresetStore.storageKey: data],
            forName: appDomain
        )
        defer {
            defaults.removePersistentDomain(forName: appDomain)
        }

        let loaded = LayoutPresetStore.loadSharedAppState(defaults: defaults, appDomains: [appDomain])

        XCTAssertEqual(loaded.presets.first?.id, "saved")
        XCTAssertEqual(loaded.presets.first?.name, "Saved Layout")
        XCTAssertEqual(loaded.defaultPresetID, "saved")
    }

    func testLoadSharedAppStateFallsBackToLegacyAppDomainPresets() throws {
        let suiteName = "run.libo.datalayer-studio.layout-preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyDomain = "\(suiteName).legacy"

        let now = Date(timeIntervalSince1970: 0)
        let state = LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: "legacy",
                    name: "Legacy Layout",
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: "legacy"
        )
        let data = try JSONEncoder().encode(state)
        defaults.setPersistentDomain(
            [LayoutPresetStore.storageKey: data],
            forName: legacyDomain
        )
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        let loaded = LayoutPresetStore.loadSharedAppState(defaults: defaults, appDomains: [legacyDomain])

        XCTAssertEqual(loaded.presets.first?.id, "legacy")
        XCTAssertEqual(loaded.presets.first?.name, "Legacy Layout")
        XCTAssertEqual(loaded.defaultPresetID, "legacy")
    }
}
