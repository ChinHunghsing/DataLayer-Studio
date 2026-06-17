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

    var sanitized: LayoutPresetState {
        var usedIDs = Set<String>()
        var usedNames = Set<String>()
        var defaultIDMap: [String: String] = [:]
        var sanitizedPresets: [LayoutPreset] = []

        for preset in presets {
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let sourceID = preset.id.trimmingCharacters(in: .whitespacesAndNewlines)

            var sanitizedPreset = preset
            sanitizedPreset.id = Self.uniquePresetID(preferredID: sourceID, usedIDs: &usedIDs)
            sanitizedPreset.name = Self.uniquePresetName(name, usedNames: &usedNames)
            sanitizedPreset.layout = preset.layout.sanitized

            if !sourceID.isEmpty, defaultIDMap[sourceID] == nil {
                defaultIDMap[sourceID] = sanitizedPreset.id
            }

            sanitizedPresets.append(sanitizedPreset)
        }

        return LayoutPresetState(
            presets: sanitizedPresets,
            defaultPresetID: defaultPresetID
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { defaultIDMap[$0] }
        )
    }

    private static func uniquePresetID(preferredID: String, usedIDs: inout Set<String>) -> String {
        let trimmedID = preferredID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, !usedIDs.contains(trimmedID) {
            usedIDs.insert(trimmedID)
            return trimmedID
        }

        var id = UUID().uuidString
        while usedIDs.contains(id) {
            id = UUID().uuidString
        }
        usedIDs.insert(id)
        return id
    }

    private static func uniquePresetName(_ baseName: String, usedNames: inout Set<String>) -> String {
        let normalizedBaseName = normalizedPresetName(baseName)
        if !usedNames.contains(normalizedBaseName) {
            usedNames.insert(normalizedBaseName)
            return baseName
        }

        var suffix = 2
        var candidate = "\(baseName) \(suffix)"
        while usedNames.contains(normalizedPresetName(candidate)) {
            suffix += 1
            candidate = "\(baseName) \(suffix)"
        }
        usedNames.insert(normalizedPresetName(candidate))
        return candidate
    }

    private static func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
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
        return state.sanitized
    }

    func save(_ state: LayoutPresetState) {
        guard let data = try? JSONEncoder().encode(state.sanitized) else { return }
        defaults.set(data, forKey: key)
    }
}
