import XCTest
@testable import OverlayStudio

final class RecentTimelineProjectStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RecentTimelineProjectStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordPersistsSecurityScopedBookmarkAndMovesProjectToFront() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.dlsproj")
        let secondURL = directory.appendingPathComponent("second.dlsproj")
        try Data("{}".utf8).write(to: firstURL)
        try Data("{}".utf8).write(to: secondURL)
        let store = RecentTimelineProjectStore(defaults: defaults)

        _ = store.record(firstURL)
        _ = store.record(secondURL)
        let projects = store.record(firstURL)

        XCTAssertEqual(projects.map(\.url), [
            firstURL.standardizedFileURL.resolvingSymlinksInPath(),
            secondURL.standardizedFileURL.resolvingSymlinksInPath()
        ])
        XCTAssertEqual(RecentTimelineProjectStore(defaults: defaults).load(), projects)
        let data = try XCTUnwrap(defaults.data(forKey: RecentTimelineProjectStore.storageKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNotNil(json.first?["bookmarkData"] as? String)
    }

    func testRecordKeepsOnlyMaximumRecentProjects() {
        let store = RecentTimelineProjectStore(defaults: defaults)

        for index in 0..<(RecentTimelineProjectStore.maximumCount + 3) {
            _ = store.record(URL(fileURLWithPath: "/tmp/project-\(index).dlsproj"))
        }

        let projects = store.load()
        XCTAssertEqual(projects.count, RecentTimelineProjectStore.maximumCount)
        XCTAssertEqual(projects.first?.url.path, "/tmp/project-12.dlsproj")
    }

    func testLoadsLegacyEntryWithoutLastOpenedDate() throws {
        let path = "/tmp/legacy-project.dlsproj"
        let data = try JSONSerialization.data(withJSONObject: [["path": path]])
        defaults.set(data, forKey: RecentTimelineProjectStore.storageKey)

        let projects = RecentTimelineProjectStore(defaults: defaults).load()

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].url.path, path)
        XCTAssertNil(projects[0].lastOpenedAt)
    }

    func testRecordAddsLastOpenedDateAndAvailability() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-project-\(UUID().uuidString).dlsproj")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let project = try XCTUnwrap(RecentTimelineProjectStore(defaults: defaults).record(url).first)

        XCTAssertNotNil(project.lastOpenedAt)
        XCTAssertTrue(project.isAvailable)
    }
}
