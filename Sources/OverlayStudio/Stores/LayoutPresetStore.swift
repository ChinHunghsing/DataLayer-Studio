import Foundation
import OverlayCore

struct LayoutPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var layout: OverlayLayout
    var createdAt: Date
    var updatedAt: Date
}

struct LayoutPresetState: Codable, Equatable {
    var presets: [LayoutPreset]
    var defaultPresetID: String?

    static let empty = LayoutPresetState(presets: [], defaultPresetID: nil)
}

struct LayoutPresetStore {
    private let defaults: UserDefaults
    private let key = "run.libo.overlay-studio.layout-presets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LayoutPresetState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(LayoutPresetState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(_ state: LayoutPresetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
