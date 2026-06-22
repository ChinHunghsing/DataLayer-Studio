import Foundation
import OverlayCore
import Security

enum OpenWeatherKeyStore {
    private static let service = "run.libo.datalayer-studio.openweather"
    private static let account = "api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard !trimmed.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

struct OpenWeatherRecord: Codable, Equatable {
    var timestamp: Date
    var temperatureCelsius: Int?
    var humidityPercent: Int?
    var summary: String?
}

final class OpenWeatherService {
    typealias DataLoader = (URL) async throws -> Data

    private let cacheDirectory: URL
    private let dataLoader: DataLoader

    init(
        cacheDirectory: URL = OpenWeatherService.defaultCacheDirectory(),
        dataLoader: @escaping DataLoader = OpenWeatherService.defaultLoadData(from:)
    ) {
        self.cacheDirectory = cacheDirectory
        self.dataLoader = dataLoader
    }

    func enrichedSeries(_ series: TelemetrySeries, apiKey: String, language: String) async throws -> TelemetrySeries {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              let anchor = Self.anchor(in: series) else {
            return series
        }

        let records = try await weatherRecords(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            start: Self.hourStart(for: anchor.date),
            apiKey: trimmedKey,
            language: language
        )
        return Self.series(series, applying: records)
    }

    private func weatherRecords(
        latitude: Double,
        longitude: Double,
        start: Date,
        apiKey: String,
        language: String
    ) async throws -> [OpenWeatherRecord] {
        let cacheURL = cacheURL(latitude: latitude, longitude: longitude, start: start)
        if let cached = Self.readCache(cacheURL) {
            return cached
        }

        let url = try requestURL(
            latitude: latitude,
            longitude: longitude,
            start: start,
            apiKey: apiKey,
            language: language
        )
        let data = try await dataLoader(url)
        let response = try JSONDecoder().decode(OpenWeatherTimelineResponse.self, from: data)
        let records = response.data.map(\.record)
        try Self.writeCache(records, to: cacheURL)
        return records
    }

    private func requestURL(
        latitude: Double,
        longitude: Double,
        start: Date,
        apiKey: String,
        language: String
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openweathermap.org"
        components.path = "/data/4.0/onecall/timeline/1h"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: language),
            URLQueryItem(name: "appid", value: apiKey)
        ]
        guard let url = components.url else { throw OpenWeatherError.invalidURL }
        return url
    }

    private func cacheURL(latitude: Double, longitude: Double, start: Date) -> URL {
        let fileName = String(
            format: "%.3f_%.3f_%lld.json",
            locale: Locale(identifier: "en_US_POSIX"),
            Self.rounded(latitude),
            Self.rounded(longitude),
            Int64(start.timeIntervalSince1970)
        )
        return cacheDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func defaultLoadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenWeatherError.requestFailed(statusCode: -1)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw OpenWeatherError.requestFailed(statusCode: httpResponse.statusCode)
        }
        return data
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DataLayerStudio/OpenWeather", isDirectory: true)
    }

    private static func readCache(_ url: URL) -> [OpenWeatherRecord]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([OpenWeatherRecord].self, from: data)
    }

    private static func writeCache(_ records: [OpenWeatherRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }

    private static func anchor(in series: TelemetrySeries) -> (date: Date, latitude: Double, longitude: Double)? {
        series.samples.compactMap { sample in
            guard let date = sample.date,
                  let latitude = sample.latitude,
                  let longitude = sample.longitude else { return nil }
            return (date, latitude, longitude)
        }.first
    }

    private static func hourStart(for date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3600) * 3600)
    }

    private static func rounded(_ coordinate: Double) -> Double {
        (coordinate * 1000).rounded() / 1000
    }

    static func series(_ series: TelemetrySeries, applying records: [OpenWeatherRecord]) -> TelemetrySeries {
        guard !records.isEmpty else { return series }
        let samples = series.samples.map { sample -> TelemetrySample in
            guard let date = sample.date,
                  let record = nearestRecord(to: date, in: records) else {
                return sample
            }
            var enriched = sample
            enriched.weatherTemperatureCelsius = record.temperatureCelsius
            enriched.weatherHumidityPercent = record.humidityPercent
            enriched.weatherSummary = record.summary
            return enriched
        }
        return TelemetrySeries(samples: samples)
    }

    private static func nearestRecord(to date: Date, in records: [OpenWeatherRecord]) -> OpenWeatherRecord? {
        // ponytail: OpenWeather 1h pages cap at 20 records; linear nearest lookup stays tiny.
        let nearest = records.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
        guard let nearest,
              abs(nearest.timestamp.timeIntervalSince(date)) <= 90 * 60 else {
            return nil
        }
        return nearest
    }
}

enum OpenWeatherError: LocalizedError {
    case invalidURL
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "OpenWeather request URL was invalid."
        case .requestFailed(let statusCode):
            if statusCode == 401 {
                return "OpenWeather key cannot access One Call 4.0."
            }
            if statusCode > 0 {
                return "OpenWeather request failed (\(statusCode))."
            }
            return "OpenWeather request failed."
        }
    }
}

private struct OpenWeatherTimelineResponse: Decodable {
    var data: [OpenWeatherDataPoint]
}

private struct OpenWeatherDataPoint: Decodable {
    var dt: TimeInterval
    var temp: Double?
    var humidity: Int?
    var weather: [OpenWeatherCondition]?

    var record: OpenWeatherRecord {
        OpenWeatherRecord(
            timestamp: Date(timeIntervalSince1970: dt),
            temperatureCelsius: temp.map { Int($0.rounded()) },
            humidityPercent: humidity,
            summary: weather?.first?.main
        )
    }
}

private struct OpenWeatherCondition: Decodable {
    var main: String?
}
