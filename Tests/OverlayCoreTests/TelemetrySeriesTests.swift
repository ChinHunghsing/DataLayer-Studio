import Foundation
@testable import OverlayCore
import XCTest

final class TelemetrySeriesTests: XCTestCase {
    func testDateAtElapsedExtrapolatesBeforeActivityStart() {
        let startDate = Date(timeIntervalSince1970: 1_787_000_000)
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: startDate, distanceMeters: 0),
            TelemetrySample(elapsed: 10, date: startDate.addingTimeInterval(10), distanceMeters: 30)
        ])

        XCTAssertEqual(series.activityStartDate?.timeIntervalSince1970 ?? -1, startDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(series.date(atElapsed: -7)?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(-7).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(series.date(atElapsed: 4)?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(4).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(series.date(atElapsed: 14)?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(14).timeIntervalSince1970, accuracy: 0.001)
    }

    func testDateAtElapsedUsesFirstDatedSampleToRecoverActivityStartDate() {
        let startDate = Date(timeIntervalSince1970: 1_787_000_000)
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 5, date: startDate.addingTimeInterval(5), distanceMeters: 15),
            TelemetrySample(elapsed: 10, date: startDate.addingTimeInterval(10), distanceMeters: 30)
        ])

        XCTAssertEqual(series.activityStartDate?.timeIntervalSince1970 ?? -1, startDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(series.date(atElapsed: -3)?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(-3).timeIntervalSince1970, accuracy: 0.001)
    }

    func testDateAtElapsedUsesSampleDatesAcrossPausedTimerGaps() {
        let startDate = Date(timeIntervalSince1970: 1_787_000_000)
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: startDate, distanceMeters: 0),
            TelemetrySample(elapsed: 1_249, date: startDate.addingTimeInterval(1_903), distanceMeters: 3_034)
        ])

        XCTAssertEqual(series.date(atElapsed: 1_249)?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(1_903).timeIntervalSince1970, accuracy: 0.001)
    }

    func testResamplesSparseRecordsAtOneSecondIntervals() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 3, distanceMeters: 30, speedMetersPerSecond: 3)
        ])

        XCTAssertEqual(series.samples.map(\.elapsed), [0, 1, 2, 3])
        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 20, accuracy: 0.001)
    }

    func testComputesTotalAscentFromAltitudeAndIgnoresSmallNoise() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, altitudeMeters: 10),
            TelemetrySample(elapsed: 1, altitudeMeters: 10.4),
            TelemetrySample(elapsed: 2, altitudeMeters: 12.4),
            TelemetrySample(elapsed: 3, altitudeMeters: 11.4),
            TelemetrySample(elapsed: 4, altitudeMeters: 14.4)
        ])

        XCTAssertEqual(series.sample(at: 0).totalAscentMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 1).totalAscentMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).totalAscentMeters ?? -1, 2.4, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 4).totalAscentMeters ?? -1, 5.4, accuracy: 0.001)
    }

    func testLeavesTotalAscentEmptyWhenAltitudeIsMissing() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])

        XCTAssertNil(series.sample(at: 1).totalAscentMeters)
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

    func testBackfillsStartupDistanceWhenEarlyRecordsStayAtZero() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 0),
            TelemetrySample(elapsed: 2, distanceMeters: 0),
            TelemetrySample(elapsed: 6, distanceMeters: 30)
        ])

        XCTAssertEqual(series.sample(at: 0).distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 3).distanceMeters ?? -1, 15, accuracy: 0.001)
    }

    func testBackfillsStartupCadenceFromZeroBeforeFirstCadenceRecord() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, cadence: 0),
            TelemetrySample(elapsed: 6, cadence: 180)
        ])

        XCTAssertEqual(series.sample(at: 0).cadence, 0)
        XCTAssertEqual(series.sample(at: 1).cadence, 30)
        XCTAssertEqual(series.sample(at: 2).cadence, 60)
        XCTAssertEqual(series.sample(at: 3).cadence, 90)
        XCTAssertEqual(series.sample(at: 6).cadence, 180)
    }

    func testBackfillsStartupCadenceWhenFirstRecordsHaveNoCadence() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 2),
            TelemetrySample(elapsed: 6, cadence: 180)
        ])

        XCTAssertEqual(series.sample(at: 0).cadence, 0)
        XCTAssertEqual(series.sample(at: 1).cadence, 30)
        XCTAssertEqual(series.sample(at: 2).cadence, 60)
        XCTAssertEqual(series.sample(at: 3).cadence, 90)
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

    func testStabilizesStartupSpeedDropWhenDistanceSegmentsAreConsistent() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 0.55),
            TelemetrySample(elapsed: 1, distanceMeters: 2.2, speedMetersPerSecond: 2.2),
            TelemetrySample(elapsed: 2, distanceMeters: 4.4, speedMetersPerSecond: 2.2),
            TelemetrySample(elapsed: 3, distanceMeters: 6.6, speedMetersPerSecond: 1.142),
            TelemetrySample(elapsed: 4, distanceMeters: 8.8, speedMetersPerSecond: 2.286),
            TelemetrySample(elapsed: 5, distanceMeters: 11.0, speedMetersPerSecond: 3.408),
            TelemetrySample(elapsed: 6, distanceMeters: 22.0, speedMetersPerSecond: 4.531)
        ])

        XCTAssertEqual(series.sample(at: 3).speedMetersPerSecond ?? -1, 2.2, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 3.408, accuracy: 0.001)
    }

    func testStartupPaceIgnoresSpeedSpikeBeforeDistanceMoves() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 120, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 2, distanceMeters: 120, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 3, distanceMeters: 120, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 4, distanceMeters: 120, speedMetersPerSecond: 12),
            TelemetrySample(elapsed: 5, distanceMeters: 132, speedMetersPerSecond: 2)
        ])

        let threeSecondSpeed = series.sample(at: 3).speedMetersPerSecond ?? -1
        let fourSecondSpeed = series.sample(at: 4).speedMetersPerSecond ?? -1
        let fiveSecondSpeed = series.sample(at: 5).speedMetersPerSecond ?? -1

        XCTAssertGreaterThan(threeSecondSpeed, 0.3)
        XCTAssertGreaterThan(fourSecondSpeed, threeSecondSpeed)
        XCTAssertGreaterThan(fiveSecondSpeed, fourSecondSpeed)
        XCTAssertLessThan(fourSecondSpeed, 2)
        XCTAssertEqual(series.sample(at: 4).distanceMeters ?? -1, 0, accuracy: 0.001)
    }

    func testTrimsIncompleteTailAfterUsuallyAvailableChannelsDisappear() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, latitude: 35, longitude: 139, heartRate: 130, cadence: 190, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, latitude: 35.0001, longitude: 139.0001, heartRate: 131, cadence: 192, distanceMeters: 3, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 2, latitude: 35.0002, longitude: 139.0002, heartRate: 132, cadence: 192, distanceMeters: 6, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 3, heartRate: 133, cadence: 192, distanceMeters: 9, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 4, heartRate: 134, distanceMeters: 12, speedMetersPerSecond: 3)
        ])

        XCTAssertEqual(series.duration, 2)
        XCTAssertEqual(series.samples.last?.elapsed, 2)
        XCTAssertEqual(series.sample(at: 4).distanceMeters ?? -1, 6, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 4).cadence, 192)
    }

    func testDoesNotTrimTailForChannelsAbsentThroughoutActivity() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 2, distanceMeters: 6, speedMetersPerSecond: 3)
        ])

        XCTAssertEqual(series.duration, 2)
        XCTAssertEqual(series.samples.last?.elapsed, 2)
    }

    func testActivityTrimRebasesElapsedDistanceCaloriesAndAscent() {
        let startDate = Date(timeIntervalSince1970: 1_787_000_000)
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, date: startDate, altitudeMeters: 10, distanceMeters: 0, speedMetersPerSecond: 5, totalCalories: 0),
            TelemetrySample(elapsed: 10, date: startDate.addingTimeInterval(10), altitudeMeters: 30, distanceMeters: 100, speedMetersPerSecond: 5, totalCalories: 20),
            TelemetrySample(elapsed: 20, date: startDate.addingTimeInterval(20), altitudeMeters: 60, distanceMeters: 250, speedMetersPerSecond: 5, totalCalories: 50)
        ])

        let trimmed = series.trimmed(by: ActivityTrim(startSeconds: 5, endSeconds: 15))

        XCTAssertEqual(trimmed.duration, 10, accuracy: 0.001)
        XCTAssertEqual(trimmed.samples.first?.elapsed ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(trimmed.samples.first?.distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(trimmed.samples.first?.totalCalories ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(trimmed.samples.first?.totalAscentMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(trimmed.samples.first?.date?.timeIntervalSince1970 ?? -1, startDate.addingTimeInterval(5).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(trimmed.sample(at: 10).distanceMeters ?? -1, 125, accuracy: 0.001)
        XCTAssertEqual(trimmed.sample(at: 10).totalCalories ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(trimmed.sample(at: 10).totalAscentMeters ?? -1, 25, accuracy: 0.001)
    }

    func testActivityTrimMapsOriginalElapsedToDisplayElapsed() {
        let trim = ActivityTrim(startSeconds: 20, endSeconds: 80)

        XCTAssertEqual(trim.displayElapsed(forRawElapsed: 0, sourceDuration: 100), 0, accuracy: 0.001)
        XCTAssertEqual(trim.displayElapsed(forRawElapsed: 20, sourceDuration: 100), 0, accuracy: 0.001)
        XCTAssertEqual(trim.displayElapsed(forRawElapsed: 35, sourceDuration: 100), 15, accuracy: 0.001)
        XCTAssertEqual(trim.displayElapsed(forRawElapsed: 120, sourceDuration: 100), 60, accuracy: 0.001)
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
