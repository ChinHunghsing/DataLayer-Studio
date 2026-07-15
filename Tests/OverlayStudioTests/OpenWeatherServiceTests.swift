import Foundation
import XCTest
import OverlayCore
@testable import OverlayStudio

final class OpenWeatherServiceTests: XCTestCase {
    func testWeatherKeyMigrationRetriesAfterEmptyDefaultsAndKeepsMigratedValue() throws {
        let suiteName = "OpenWeatherKeyStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("   ", forKey: "openweather.api-key")

        var legacyLoadCount = 0
        let migrated = OpenWeatherKeyStore.load(defaults: defaults) {
            legacyLoadCount += 1
            return "  legacy-key  "
        }

        XCTAssertEqual(migrated, "legacy-key")
        XCTAssertEqual(legacyLoadCount, 1)

        let reloaded = OpenWeatherKeyStore.load(defaults: defaults) {
            XCTFail("A persisted migrated key must avoid another Keychain lookup")
            return ""
        }
        XCTAssertEqual(reloaded, "legacy-key")
    }

    func testSavingWeatherKeyOnlyDeletesLegacyValueWhenUserClearsIt() throws {
        let suiteName = "OpenWeatherKeyStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var legacyDeleteCount = 0

        OpenWeatherKeyStore.save("  current-key  ", defaults: defaults) {
            legacyDeleteCount += 1
        }

        XCTAssertEqual(
            OpenWeatherKeyStore.load(defaults: defaults, legacyLoader: { "legacy-key" }),
            "current-key"
        )
        XCTAssertEqual(legacyDeleteCount, 0)

        OpenWeatherKeyStore.save("   ", defaults: defaults) {
            legacyDeleteCount += 1
        }

        XCTAssertEqual(legacyDeleteCount, 1)
        XCTAssertEqual(
            OpenWeatherKeyStore.load(defaults: defaults, legacyLoader: { "" }),
            ""
        )
    }

    func testWeatherFetchUsesLocalCacheForSameTimeAndLocation() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWeatherServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        var loadCount = 0
        let service = OpenWeatherService(cacheDirectory: cacheDirectory) { _ in
            loadCount += 1
            return Data("""
            {"data":[{"dt":3600,"temp":22.4,"humidity":58,"weather":[{"main":"Clear"}]}]}
            """.utf8)
        }
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                date: Date(timeIntervalSince1970: 3900),
                latitude: 35.6812,
                longitude: 139.7671
            )
        ])

        let first = try await service.enrichedSeries(series, apiKey: "test-key", language: "en")
        let second = try await service.enrichedSeries(series, apiKey: "test-key", language: "en")
        _ = try await service.enrichedSeries(series, apiKey: "test-key", language: "en", forceRefresh: true)

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(first.series.samples.first?.weatherTemperatureCelsius, 22)
        XCTAssertEqual(second.series.samples.first?.weatherHumidityPercent, 58)
        XCTAssertEqual(second.series.samples.first?.weatherSummary, "Clear")
    }

    func testUnauthorizedOpenWeatherErrorExplainsOneCallAccess() {
        let error = OpenWeatherError.requestFailed(statusCode: 401)

        XCTAssertEqual(error.localizedDescription, "OpenWeather key cannot access One Call 4.0.")
    }

    func testWeatherCacheIsSeparatedByLanguage() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWeatherServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        var summaries = ["Clouds", "多云"]
        let service = OpenWeatherService(cacheDirectory: cacheDirectory) { _ in
            let summary = summaries.removeFirst()
            return Data("""
            {"data":[{"dt":3600,"temp":22,"humidity":58,"weather":[{"main":"\(summary)"}]}]}
            """.utf8)
        }
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                date: Date(timeIntervalSince1970: 3900),
                latitude: 35.6812,
                longitude: 139.7671
            )
        ])

        let english = try await service.enrichedSeries(series, apiKey: "test-key", language: "en")
        let chinese = try await service.enrichedSeries(series, apiKey: "test-key", language: "zh_cn")

        XCTAssertEqual(english.series.samples.first?.weatherSummary, "Clouds")
        XCTAssertEqual(chinese.series.samples.first?.weatherSummary, "多云")
    }

    func testWeatherFetchesPreviousPageWhenFirstPageStartsAfterActivity() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWeatherServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        var starts: [Int] = []
        let service = OpenWeatherService(cacheDirectory: cacheDirectory) { url in
            let start = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "start" })?
                .value ?? "") ?? 0
            starts.append(start)
            if starts.count == 1 {
                return Data(#"{"data":[{"dt":200000,"temp":18,"humidity":60,"weather":[{"main":"Clouds"}]}]}"#.utf8)
            }
            return Data(#"{"data":[{"dt":100000,"temp":24,"humidity":70,"weather":[{"main":"Rain"}]}]}"#.utf8)
        }
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                date: Date(timeIntervalSince1970: 100300),
                latitude: 34.683,
                longitude: 135.532
            )
        ])

        let enriched = try await service.enrichedSeries(series, apiKey: "test-key", language: "en")

        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(enriched.series.samples.first?.weatherTemperatureCelsius, 24)
        XCTAssertEqual(enriched.series.samples.first?.weatherHumidityPercent, 70)
        XCTAssertEqual(enriched.series.samples.first?.weatherSummary, "Rain")
    }

    func testWeatherUsesNearestRecordAcrossRecentTimelineGap() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                date: Date(timeIntervalSince1970: 1_000),
                latitude: 34.683,
                longitude: 135.532
            )
        ])
        let enriched = OpenWeatherService.series(series, applying: [
            OpenWeatherRecord(
                timestamp: Date(timeIntervalSince1970: 1_000 + 3 * 3600),
                temperatureCelsius: 24,
                humidityPercent: 70,
                summary: "Clouds"
            )
        ])

        XCTAssertEqual(enriched.samples.first?.weatherTemperatureCelsius, 24)
        XCTAssertEqual(enriched.samples.first?.weatherHumidityPercent, 70)
        XCTAssertEqual(enriched.samples.first?.weatherSummary, "Clouds")
    }
}
