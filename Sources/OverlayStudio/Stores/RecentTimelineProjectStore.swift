import Foundation

struct RecentTimelineProject: Identifiable, Equatable {
    var url: URL
    var lastOpenedAt: Date?

    var id: String { url.standardizedFileURL.resolvingSymlinksInPath().path }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var isAvailable: Bool { FileManager.default.fileExists(atPath: url.path) }
}

final class RecentTimelineProjectStore {
    static let storageKey = "run.libo.overlay-studio.recent-timeline-projects.v1"
    static let maximumCount = 10

    private struct StoredProject: Codable, Equatable {
        var path: String
        var bookmarkData: Data?
        var lastOpenedAt: Date?
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = RecentTimelineProjectStore.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RecentTimelineProject] {
        let stored = loadStoredProjects()
        var refreshed: [StoredProject] = []
        var projects: [RecentTimelineProject] = []

        for item in stored {
            let resolved = resolve(item)
            let url = resolved.url.standardizedFileURL.resolvingSymlinksInPath()
            let path = url.path
            guard !projects.contains(where: { $0.id == path }) else { continue }
            projects.append(RecentTimelineProject(url: url, lastOpenedAt: item.lastOpenedAt))
            refreshed.append(StoredProject(
                path: path,
                bookmarkData: resolved.bookmarkData,
                lastOpenedAt: item.lastOpenedAt
            ))
        }

        if refreshed != stored {
            save(refreshed)
        }
        return projects
    }

    func record(_ url: URL) -> [RecentTimelineProject] {
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = standardizedURL.path
        let existing = loadStoredProjects().first { $0.path == path }
        let bookmarkData = makeBookmark(for: standardizedURL) ?? existing?.bookmarkData
        var stored = loadStoredProjects().filter { $0.path != path }
        stored.insert(StoredProject(path: path, bookmarkData: bookmarkData, lastOpenedAt: Date()), at: 0)
        save(Array(stored.prefix(Self.maximumCount)))
        return load()
    }

    func replace(_ project: RecentTimelineProject, with url: URL) -> [RecentTimelineProject] {
        let oldPath = project.url.standardizedFileURL.resolvingSymlinksInPath().path
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let newPath = standardizedURL.path
        let bookmarkData = makeBookmark(for: standardizedURL)
        var stored = loadStoredProjects().filter { $0.path != oldPath && $0.path != newPath }
        stored.insert(
            StoredProject(path: newPath, bookmarkData: bookmarkData, lastOpenedAt: Date()),
            at: 0
        )
        save(Array(stored.prefix(Self.maximumCount)))
        return load()
    }

    func remove(_ url: URL) -> [RecentTimelineProject] {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        save(loadStoredProjects().filter { $0.path != path })
        return load()
    }

    private func resolve(_ stored: StoredProject) -> (url: URL, bookmarkData: Data?) {
        guard let bookmarkData = stored.bookmarkData else {
            return (URL(fileURLWithPath: stored.path), nil)
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return (URL(fileURLWithPath: stored.path), bookmarkData)
        }
        return (url, isStale ? (makeBookmark(for: url) ?? bookmarkData) : bookmarkData)
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func loadStoredProjects() -> [StoredProject] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredProject].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(Self.maximumCount))
    }

    private func save(_ projects: [StoredProject]) {
        guard let data = try? JSONEncoder().encode(Array(projects.prefix(Self.maximumCount))) else { return }
        defaults.set(data, forKey: key)
    }
}
