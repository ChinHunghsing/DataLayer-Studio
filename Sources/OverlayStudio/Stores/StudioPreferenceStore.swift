import Foundation
import OverlayCore

struct StudioPreferenceState: Codable, Equatable {
    var showGrid: Bool
    var safeAreaInsetPercent: Double
    var distanceUnit: OverlayDistanceUnit
    var userExportPresets: [ExportPreset]

    static let `default` = StudioPreferenceState(
        showGrid: false,
        safeAreaInsetPercent: 5,
        distanceUnit: .kilometers,
        userExportPresets: []
    )

    init(
        showGrid: Bool,
        safeAreaInsetPercent: Double,
        distanceUnit: OverlayDistanceUnit,
        userExportPresets: [ExportPreset] = []
    ) {
        self.showGrid = showGrid
        self.safeAreaInsetPercent = safeAreaInsetPercent
        self.distanceUnit = distanceUnit
        self.userExportPresets = userExportPresets
    }

    // Decoded manually so preferences saved by older versions (which lack
    // `safeAreaInsetPercent` and carry retired grid-snapping fields) still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showGrid = try container.decodeIfPresent(Bool.self, forKey: .showGrid) ?? Self.default.showGrid
        safeAreaInsetPercent = try container.decodeIfPresent(Double.self, forKey: .safeAreaInsetPercent)
            ?? Self.default.safeAreaInsetPercent
        distanceUnit = try container.decodeIfPresent(OverlayDistanceUnit.self, forKey: .distanceUnit)
            ?? Self.default.distanceUnit
        userExportPresets = try container.decodeIfPresent([ExportPreset].self, forKey: .userExportPresets) ?? []
    }

    var sanitized: StudioPreferenceState {
        StudioPreferenceState(
            showGrid: showGrid,
            safeAreaInsetPercent: Self.sanitizedSafeAreaInsetPercent(safeAreaInsetPercent),
            distanceUnit: distanceUnit,
            userExportPresets: userExportPresets.filter {
                !$0.isBuiltIn
                    && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.codec.exportMode == $0.exportMode
            }
        )
    }

    static func sanitizedSafeAreaInsetPercent(_ value: Double) -> Double {
        guard value.isFinite else { return Self.default.safeAreaInsetPercent }
        return min(20, max(0, value))
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
