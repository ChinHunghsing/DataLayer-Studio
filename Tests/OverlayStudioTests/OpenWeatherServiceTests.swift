import Foundation
import XCTest
import OverlayCore
@testable import OverlayStudio

final class OpenWeatherServiceTests: XCTestCase {
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
        XCTAssertEqual(first.samples.first?.weatherTemperatureCelsius, 22)
        XCTAssertEqual(second.samples.first?.weatherHumidityPercent, 58)
        XCTAssertEqual(second.samples.first?.weatherSummary, "Clear")
    }

    func testUnauthorizedOpenWeatherErrorExplainsOneCallAccess() {
        let error = OpenWeatherError.requestFailed(statusCode: 401)

        XCTAssertEqual(error.localizedDescription, "OpenWeather key cannot access One Call 4.0.")
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
        XCTAssertEqual(enriched.samples.first?.weatherTemperatureCelsius, 24)
        XCTAssertEqual(enriched.samples.first?.weatherHumidityPercent, 70)
        XCTAssertEqual(enriched.samples.first?.weatherSummary, "Rain")
    }
}
