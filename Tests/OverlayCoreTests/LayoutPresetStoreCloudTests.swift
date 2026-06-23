@testable import OverlayCore
import XCTest

final class LayoutPresetStoreCloudTests: XCTestCase {
    func testLoadPrefersCloudPresetsAndMirrorsThemLocally() throws {
        let defaults = try makeDefaults()
        let localState = makeState(id: "local", name: "Local")
        let cloudState = makeState(id: "cloud", name: "Cloud")
        defaults.set(try JSONEncoder().encode(localState), forKey: LayoutPresetStore.storageKey)

        let store = LayoutPresetStore(
            defaults: defaults,
            loadCloudData: { try? JSONEncoder().encode(cloudState) },
            saveCloudData: nil,
            synchronizeCloudStore: nil
        )

        let loaded = store.load()
        let mirrored = try XCTUnwrap(defaults.data(forKey: LayoutPresetStore.storageKey))
        let mirroredState = try JSONDecoder().decode(LayoutPresetState.self, from: mirrored)

        XCTAssertEqual(loaded.presets.first?.id, "cloud")
        XCTAssertEqual(mirroredState.presets.first?.id, "cloud")
    }

    func testLoadBackfillsCloudWhenOnlyLocalPresetsExist() throws {
        let defaults = try makeDefaults()
        let localState = makeState(id: "local", name: "Local")
        defaults.set(try JSONEncoder().encode(localState), forKey: LayoutPresetStore.storageKey)
        var cloudData: Data?

        let store = LayoutPresetStore(
            defaults: defaults,
            loadCloudData: { nil },
            saveCloudData: { cloudData = $0 },
            synchronizeCloudStore: nil
        )

        let loaded = store.load()
        let savedCloudData = try XCTUnwrap(cloudData)
        let savedCloudState = try JSONDecoder().decode(LayoutPresetState.self, from: savedCloudData)

        XCTAssertEqual(loaded.presets.first?.id, "local")
        XCTAssertEqual(savedCloudState.presets.first?.id, "local")
    }

    func testSynchronizeCloudReportsStoreResult() throws {
        let defaults = try makeDefaults()
        let store = LayoutPresetStore(
            defaults: defaults,
            loadCloudData: nil,
            saveCloudData: nil,
            synchronizeCloudStore: { true }
        )

        XCTAssertTrue(store.canRequestCloudSync)
        XCTAssertTrue(store.synchronizeCloud())
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "run.libo.datalayer-studio.layout-cloud-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeState(id: String, name: String) -> LayoutPresetState {
        let now = Date(timeIntervalSince1970: 0)
        return LayoutPresetState(
            presets: [
                LayoutPreset(
                    id: id,
                    name: name,
                    layout: .default,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            defaultPresetID: id
        )
    }
}
