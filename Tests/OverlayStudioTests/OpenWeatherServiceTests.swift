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
}
