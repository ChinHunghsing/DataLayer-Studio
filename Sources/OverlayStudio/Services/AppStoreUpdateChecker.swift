import Foundation

struct AppStoreUpdate: Identifiable, Equatable {
    let version: String
    let url = PurchaseAuthorizationStore.fullVersionURL

    var id: String { version }
}

enum AppStoreUpdateChecker {
    private static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=6782545770&country=cn")!

    static func availableUpdate(
        currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) async -> AppStoreUpdate? {
        guard let currentVersion, !currentVersion.isEmpty else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: lookupURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let latestVersion = try JSONDecoder().decode(LookupResponse.self, from: data).results.first?.version,
                  isNewer(latestVersion, than: currentVersion) else {
                return nil
            }
            return AppStoreUpdate(version: latestVersion)
        } catch {
            return nil
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    private struct LookupResponse: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let version: String
        }
    }
}
