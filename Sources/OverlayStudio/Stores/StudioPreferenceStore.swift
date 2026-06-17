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
    private let defaults: UserDefaults
    private let key = "run.libo.overlay-studio.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StudioPreferenceState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(StudioPreferenceState.self, from: data) else {
            return .default
        }
        return state.sanitized
    }

    func save(_ state: StudioPreferenceState) {
        guard let data = try? JSONEncoder().encode(state.sanitized) else { return }
        defaults.set(data, forKey: key)
    }
}
