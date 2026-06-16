import Foundation
@testable import OverlayCore
import XCTest

final class TelemetryTimeSyncTests: XCTestCase {
    func testLegacyPositiveOffsetDelaysFITStart() {
        let sync = TelemetryTimeSync.legacyOffset(12)

        XCTAssertEqual(sync.fitElapsed(forVideoTime: 0), 0)
        XCTAssertEqual(sync.fitElapsed(forVideoTime: 12), 0)
        XCTAssertEqual(sync.fitElapsed(forVideoTime: 14.5), 2.5, accuracy: 0.0001)
    }

    func testNegativeOffsetStartsVideoMidFIT() {
        let sync = TelemetryTimeSync.legacyOffset(-300)

        XCTAssertEqual(sync.fitElapsed(forVideoTime: 0), 300)
        XCTAssertEqual(sync.fitElapsed(forVideoTime: 10), 310)
    }

    func testExplicitSyncPointMapsVideoToFIT() {
        let sync = TelemetryTimeSync(videoSyncTime: 4, fitSyncTime: 120)

        XCTAssertEqual(sync.fitElapsed(forVideoTime: 0), 116)
        XCTAssertEqual(sync.fitElapsed(forVideoTime: 4), 120)
        XCTAssertEqual(sync.fitElapsed(forVideoTime: 9), 125)
    }

    func testTelemetrySeriesClampsOutsideActivityRange() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 2),
            TelemetrySample(elapsed: 10, distanceMeters: 100, speedMetersPerSecond: 4)
        ])

        XCTAssertEqual(series.sample(at: -5).elapsed, 0)
        XCTAssertEqual(series.sample(at: 15).elapsed, 10)
        XCTAssertEqual(series.sample(at: 15).distanceMeters ?? -1, 100)
    }
}

