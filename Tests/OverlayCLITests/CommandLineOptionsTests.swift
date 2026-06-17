import XCTest
@testable import overlay

final class CommandLineOptionsTests: XCTestCase {
    func testBitrateArgumentUsesKbpsAtGuiMaximum() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--bitrate", "1000000"
        ])

        XCTAssertEqual(options.averageBitRate, 1_000_000_000)
    }

    func testBitrateArgumentKeepsLegacyBpsAboveGuiMaximum() throws {
        let options = try CommandLineOptions.parse(arguments: [
            "overlay",
            "--video", "run.mov",
            "--fit", "activity.fit",
            "--output", "overlay.mov",
            "--bitrate", "12000000"
        ])

        XCTAssertEqual(options.averageBitRate, 12_000_000)
    }
}
