import Foundation

public struct LayoutPreset: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var layout: OverlayLayout
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        layout: OverlayLayout,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LayoutPresetState: Codable, Equatable {
    public var presets: [LayoutPreset]
    public var defaultPresetID: String?

    public static let empty = LayoutPresetState(presets: [], defaultPresetID: nil)

    public init(presets: [LayoutPreset], defaultPresetID: String?) {
        self.presets = presets
        self.defaultPresetID = defaultPresetID
    }

    public var sanitized: LayoutPresetState {
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

    public func preset(matching reference: String) -> LayoutPreset? {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else { return nil }

        if let preset = presets.first(where: { $0.id == trimmedReference }) {
            return preset
        }

        return presets.first {
            $0.name.caseInsensitiveCompare(trimmedReference) == .orderedSame
        }
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

public struct LayoutPresetStore {
    public static let storageKey = "run.libo.overlay-studio.layout-presets.v1"
    public static let sharedAppDomains = DataLayerStudioDefaults.appDomains

    private let defaults: UserDefaults
    private let key: String
    private let loadCloudData: (() -> Data?)?
    private let saveCloudData: ((Data) -> Void)?
    private let synchronizeCloudStore: (() -> Bool)?

    public init(defaults: UserDefaults = .standard, key: String = Self.storageKey) {
        let ubiquitousStore = NSUbiquitousKeyValueStore.default
        self.init(
            defaults: defaults,
            key: key,
            loadCloudData: {
                ubiquitousStore.synchronize()
                return ubiquitousStore.data(forKey: key)
            },
            saveCloudData: { data in
                ubiquitousStore.set(data, forKey: key)
                ubiquitousStore.synchronize()
            },
            synchronizeCloudStore: {
                ubiquitousStore.synchronize()
            }
        )
    }

    init(
        defaults: UserDefaults,
        key: String = Self.storageKey,
        loadCloudData: (() -> Data?)?,
        saveCloudData: ((Data) -> Void)?,
        synchronizeCloudStore: (() -> Bool)?
    ) {
        self.defaults = defaults
        self.key = key
        self.loadCloudData = loadCloudData
        self.saveCloudData = saveCloudData
        self.synchronizeCloudStore = synchronizeCloudStore
    }

    public var cloudNotificationKey: String {
        key
    }

    public var canRequestCloudSync: Bool {
        synchronizeCloudStore != nil
    }

    public func load() -> LayoutPresetState {
        let localState = Self.decodeState(from: defaults.data(forKey: key))
        let cloudState = Self.decodeState(from: loadCloudData?())

        if !cloudState.presets.isEmpty {
            if cloudState != localState {
                saveLocal(cloudState)
            }
            return cloudState
        }

        if !localState.presets.isEmpty {
            saveCloud(localState)
        }
        return localState
    }

    public func loadIncludingSharedAppDomains(
        appDomains: [String] = DataLayerStudioDefaults.appDomains
    ) -> LayoutPresetState {
        let state = load()
        if !state.presets.isEmpty {
            return state
        }

        for domain in appDomains {
            let data = defaults.persistentDomain(forName: domain)?[Self.storageKey] as? Data
            let state = Self.decodeState(from: data)
            if !state.presets.isEmpty {
                save(state)
                return state
            }
        }

        return .empty
    }

    public func save(_ state: LayoutPresetState) {
        guard let data = Self.encodeState(state) else { return }
        defaults.set(data, forKey: key)
        saveCloudData?(data)
    }

    @discardableResult
    public func synchronizeCloud() -> Bool {
        synchronizeCloudStore?() ?? false
    }

    public static func loadSharedAppState(
        defaults: UserDefaults = .standard,
        appDomains: [String] = DataLayerStudioDefaults.appDomains
    ) -> LayoutPresetState {
        let store = defaults === UserDefaults.standard
            ? LayoutPresetStore(defaults: defaults)
            : LayoutPresetStore(
                defaults: defaults,
                loadCloudData: nil,
                saveCloudData: nil,
                synchronizeCloudStore: nil
            )
        return store.loadIncludingSharedAppDomains(appDomains: appDomains)
    }

    private func saveLocal(_ state: LayoutPresetState) {
        guard let data = Self.encodeState(state) else { return }
        defaults.set(data, forKey: key)
    }

    private func saveCloud(_ state: LayoutPresetState) {
        guard let data = Self.encodeState(state) else { return }
        saveCloudData?(data)
    }

    private static func encodeState(_ state: LayoutPresetState) -> Data? {
        try? JSONEncoder().encode(state.sanitized)
    }

    private static func decodeState(from data: Data?) -> LayoutPresetState {
        guard let data,
              let state = try? JSONDecoder().decode(LayoutPresetState.self, from: data) else {
            return .empty
        }
        return state.sanitized
    }
}
