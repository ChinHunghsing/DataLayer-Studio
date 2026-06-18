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

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 1).speedMetersPerSecond ?? -1, series.sample(at: 0).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 10).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
    }

    func testReplacesEarlyZeroSpeedWhenDistanceIsIncreasing() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 30, speedMetersPerSecond: 0)
        ])

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 5).speedMetersPerSecond ?? -1, series.sample(at: 0).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 10).speedMetersPerSecond ?? -1, 3, accuracy: 0.001)
    }

    func testBackfillsPlausibleStartupDistanceWhenFirstDistanceArrivesLate() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 6, distanceMeters: 30)
        ])

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 1.25, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 5, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 1).speedMetersPerSecond ?? -1, series.sample(at: 0).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 6).speedMetersPerSecond ?? -1, 5, accuracy: 0.001)
    }

    func testStartupPaceRampsFromSlowToFastWhenDistanceArrivesLate() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 6, distanceMeters: 30)
        ])

        let startSpeed = series.sample(at: 0).speedMetersPerSecond ?? -1
        let oneSecondSpeed = series.sample(at: 1).speedMetersPerSecond ?? -1
        let threeSecondSpeed = series.sample(at: 3).speedMetersPerSecond ?? -1
        let endSpeed = series.sample(at: 6).speedMetersPerSecond ?? -1

        XCTAssertGreaterThan(startSpeed, 0.3)
        XCTAssertGreaterThan(oneSecondSpeed, startSpeed)
        XCTAssertGreaterThan(threeSecondSpeed, oneSecondSpeed)
        XCTAssertGreaterThan(endSpeed, threeSecondSpeed)
        XCTAssertGreaterThan(1000 / startSpeed, 1000 / oneSecondSpeed)
        XCTAssertGreaterThan(1000 / oneSecondSpeed, 1000 / threeSecondSpeed)
    }

    func testKeepsImplausibleStartupDistanceAsBaselineOffset() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 2, distanceMeters: 1000)
        ])

        XCTAssertEqual(series.sample(at: 0).distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertLessThan(series.sample(at: 1).speedMetersPerSecond ?? 1, 0.3)
    }
}
