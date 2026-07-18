import XCTest
@testable import OverlayCore
@testable import OverlayStudio

@MainActor
final class CompatibilityFixtureTests: XCTestCase {
    func testV023ProjectAndPresetFixturesLoad() throws {
        let model = StudioModel()
        let data = try Data(contentsOf: fixtureURL(version: "v0.2.3", extension: "dlsproj"))
        XCTAssertNil(try JSONDecoder().decode(TimelineProject.self, from: data).previewTime)
        try model.loadTimelineProject(
            from: data,
            loadAssets: false
        )

        let project = model.currentTimelineProject
        XCTAssertEqual(project.schemaVersion, 2)
        XCTAssertEqual(project.outputWidth, 1280)
        XCTAssertEqual(project.outputHeight, 720)
        XCTAssertEqual(project.framesPerSecond, 30)
        XCTAssertEqual(project.assets.map(\.id), ["video-v023", "activity-v023"])
        XCTAssertTrue(project.assets.allSatisfy { $0.wallClockSource == nil && $0.weatherRecords == nil })
        XCTAssertFalse(try XCTUnwrap(project.tracks.last?.clips.first).isAlignmentPending)
        XCTAssertEqual(project.sourceMatchPoint?.videoSourceTime, 10)
        XCTAssertEqual(project.exportSettings?.bitRateKbps, 9_000)
        XCTAssertEqual(model.previewTime, 1)

        let presetModel = try isolatedModel()
        defer { presetModel.defaults.removePersistentDomain(forName: presetModel.suiteName) }
        XCTAssertEqual(
            presetModel.model.importLayoutPresets(
                from: fixtureURL(version: "v0.2.3", extension: "dlspreset")
            ),
            1
        )
        let preset = try XCTUnwrap(presetModel.model.layoutPresets.first { $0.id == "preset-v023" })
        XCTAssertEqual(preset.id, "preset-v023")
        XCTAssertEqual(preset.name, "Fixture 0.2.3")
        let weather = try XCTUnwrap(preset.layout.elements.first)
        XCTAssertEqual(weather.kind, .weather)
        XCTAssertNil(weather.customization.manualWeatherTemperatureCelsius)
        XCTAssertNil(weather.customization.manualWeatherHumidityPercent)
        XCTAssertNil(weather.customization.showsWeatherHumidity)
    }

    func testV034ProjectAndPresetFixturesLoad() throws {
        let model = StudioModel()
        try model.loadTimelineProject(
            from: Data(contentsOf: fixtureURL(version: "v0.3.4", extension: "dlsproj")),
            loadAssets: false
        )

        let project = model.currentTimelineProject
        XCTAssertEqual(project.schemaVersion, 2)
        XCTAssertEqual(project.outputWidth, 1920)
        XCTAssertEqual(project.outputHeight, 1080)
        XCTAssertEqual(project.framesPerSecond, 29.97, accuracy: 1e-9)
        XCTAssertEqual(project.assets.first?.wallClockSource, .recordingMetadata)
        XCTAssertEqual(project.assets.last?.wallClockSource, .activityMetadata)
        let weatherRecord = try XCTUnwrap(project.assets.last?.weatherRecords?.first)
        XCTAssertEqual(weatherRecord.temperatureCelsius, 24)
        XCTAssertEqual(weatherRecord.humidityPercent, 61)
        XCTAssertEqual(weatherRecord.summary, "Cloudy")
        XCTAssertTrue(try XCTUnwrap(project.tracks.last?.clips.first).isAlignmentPending)
        XCTAssertEqual(project.sourceMatchPoint?.activitySourceTime, 20)
        XCTAssertEqual(project.exportSettings?.bitRateKbps, 12_000)
        XCTAssertEqual(model.previewTime, 42.5, accuracy: 1e-9)

        let presetModel = try isolatedModel()
        defer { presetModel.defaults.removePersistentDomain(forName: presetModel.suiteName) }
        XCTAssertEqual(
            presetModel.model.importLayoutPresets(
                from: fixtureURL(version: "v0.3.4", extension: "dlspreset")
            ),
            1
        )
        let preset = try XCTUnwrap(presetModel.model.layoutPresets.first { $0.id == "preset-v034" })
        XCTAssertEqual(preset.id, "preset-v034")
        XCTAssertEqual(preset.name, "Fixture 0.3.4")
        let weather = try XCTUnwrap(preset.layout.elements.first)
        XCTAssertEqual(weather.kind, .weather)
        XCTAssertEqual(weather.customization.manualWeatherTemperatureCelsius, 26)
        XCTAssertEqual(weather.customization.manualWeatherHumidityPercent, 64)
        XCTAssertEqual(weather.customization.showsWeatherHumidity, false)
    }

    private func fixtureURL(version: String, extension fileExtension: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CompatibilityFixtures/\(version)/minimal.\(fileExtension)")
    }

    private func isolatedModel() throws -> (model: StudioModel, defaults: UserDefaults, suiteName: String) {
        let suiteName = "compatibility-fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = LayoutPresetStore(
            defaults: defaults,
            key: "\(LayoutPresetStore.storageKey).\(UUID().uuidString)",
            loadCloudData: nil,
            saveCloudData: nil,
            synchronizeCloudStore: nil
        )
        return (StudioModel(layoutPresetStore: store), defaults, suiteName)
    }
}
