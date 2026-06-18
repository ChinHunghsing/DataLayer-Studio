import Foundation
import OverlayCore

struct StudioPreferenceState: Codable, Equatable {
    var showGrid: Bool
    var gridColumns: Int
    var gridRows: Int
    var snapGaugeToGrid: Bool
    var distanceUnit: OverlayDistanceUnit

    static let `default` = StudioPreferenceState(
        showGrid: false,
        gridColumns: 12,
        gridRows: 8,
        snapGaugeToGrid: false,
        distanceUnit: .kilometers
    )

    var sanitized: StudioPreferenceState {
        StudioPreferenceState(
            showGrid: showGrid,
            gridColumns: min(64, max(2, gridColumns)),
            gridRows: min(64, max(2, gridRows)),
            snapGaugeToGrid: snapGaugeToGrid,
            distanceUnit: distanceUnit
        )
    }
}

struct StudioPreferenceStore {
    static let storageKey = "run.libo.overlay-studio.preferences.v1"

    private let defaults: UserDefaults
    private let key = Self.storageKey
    private let appDomains: [String]

    init(defaults: UserDefaults = .standard, appDomains: [String] = DataLayerStudioDefaults.appDomains) {
        self.defaults = defaults
        self.appDomains = appDomains
    }

    func load() -> StudioPreferenceState {
        if let state = Self.decodeState(defaults.data(forKey: key)) {
            return state
        }

        for domain in appDomains {
            let data = defaults.persistentDomain(forName: domain)?[key] as? Data
            if let state = Self.decodeState(data) {
                return state
            }
        }

        return .default
    }

    func save(_ state: StudioPreferenceState) {
        guard let data = try? JSONEncoder().encode(state.sanitized) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decodeState(_ data: Data?) -> StudioPreferenceState? {
        guard let data,
              let state = try? JSONDecoder().decode(StudioPreferenceState.self, from: data) else {
            return nil
        }
        return state.sanitized
    }
}
