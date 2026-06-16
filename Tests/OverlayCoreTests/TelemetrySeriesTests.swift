import Foundation
@testable import OverlayCore
import XCTest

final class TelemetrySeriesTests: XCTestCase {
    func testResamplesSparseRecordsAtOneSecondIntervals() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 3, distanceMeters: 30, speedMetersPerSecond: 3)
        ])

        XCTAssertEqual(series.samples.map(\.elapsed), [0, 1, 2, 3])
        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 20, accuracy: 0.001)
    }

    func testDerivesStartSpeedFromDistanceDeltaWhenFITSpeedIsMissing() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 30)
        ])

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 1).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
    }

    func testReplacesEarlyZeroSpeedWhenDistanceIsIncreasing() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 30, speedMetersPerSecond: 0)
        ])

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
    }
}
