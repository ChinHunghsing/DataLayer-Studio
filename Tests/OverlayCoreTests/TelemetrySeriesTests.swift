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

        XCTAssertGreaterThanOrEqual(series.sample(at: 3).speedMetersPerSecond ?? -1, 2.2)
        XCTAssertLessThan(series.sample(at: 3).speedMetersPerSecond ?? -1, 2.3)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 3.408, accuracy: 0.001)
    }

    func testStartupPaceUsesCumulativeDistanceDuringFirstSeconds() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 2, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 3, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 4, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 9, speedMetersPerSecond: 2.172),
            TelemetrySample(elapsed: 6, distanceMeters: 18, speedMetersPerSecond: 4.347),
            TelemetrySample(elapsed: 7, distanceMeters: 25, speedMetersPerSecond: 4.733),
            TelemetrySample(elapsed: 8, distanceMeters: 32, speedMetersPerSecond: 5.119),
            TelemetrySample(elapsed: 9, distanceMeters: 39, speedMetersPerSecond: 5.608),
            TelemetrySample(elapsed: 10, distanceMeters: 46, speedMetersPerSecond: 6.1)
        ])

        XCTAssertEqual(series.sample(at: 6).speedMetersPerSecond ?? -1, 3.0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 10).speedMetersPerSecond ?? -1, 4.6, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 2).speedMetersPerSecond ?? -1, series.sample(at: 1).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 5).speedMetersPerSecond ?? -1, series.sample(at: 2).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 6).speedMetersPerSecond ?? -1, series.sample(at: 5).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 10).speedMetersPerSecond ?? -1, series.sample(at: 6).speedMetersPerSecond ?? 0)
    }

    func testStartupPacePreservesRawSpeedFromFirstCompleteSample() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 0.6),
            TelemetrySample(elapsed: 1, distanceMeters: 1.8, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 2, distanceMeters: 3.6, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 3, distanceMeters: 5.9, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 4, distanceMeters: 8.8, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 5, distanceMeters: 12.5, speedMetersPerSecond: 2.5),
            TelemetrySample(elapsed: 6, distanceMeters: 18, speedMetersPerSecond: 4.347),
            TelemetrySample(elapsed: 7, distanceMeters: 25, speedMetersPerSecond: 4.733),
            TelemetrySample(elapsed: 8, distanceMeters: 32, speedMetersPerSecond: 5.119),
            TelemetrySample(elapsed: 9, distanceMeters: 39, speedMetersPerSecond: 5.608),
            TelemetrySample(
                elapsed: 10,
                latitude: 35,
                longitude: 139,
                heartRate: 150,
                cadence: 180,
                distanceMeters: 46,
                speedMetersPerSecond: 6.1
            ),
            TelemetrySample(
                elapsed: 11,
                latitude: 35.0001,
                longitude: 139.0001,
                heartRate: 151,
                cadence: 181,
                distanceMeters: 52,
                speedMetersPerSecond: 6.2
            )
        ])

        XCTAssertEqual(series.sample(at: 10).speedMetersPerSecond ?? -1, 6.1, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 11).speedMetersPerSecond ?? -1, 6.2, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 3).speedMetersPerSecond ?? -1, series.sample(at: 2).speedMetersPerSecond ?? 0)
    }

    func testStartupPaceUsesCumulativeDistanceWhenReportedSpeedStalls() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 1, distanceMeters: 1.8, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 2, distanceMeters: 3.6, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 3, distanceMeters: 5.9, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 4, distanceMeters: 8.8, speedMetersPerSecond: 1.8),
            TelemetrySample(elapsed: 5, distanceMeters: 12.5, speedMetersPerSecond: 2.5)
        ])

        XCTAssertGreaterThan(series.sample(at: 2).speedMetersPerSecond ?? -1, series.sample(at: 1).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 3).speedMetersPerSecond ?? -1, series.sample(at: 2).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 4).speedMetersPerSecond ?? -1, series.sample(at: 3).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 2.5, accuracy: 0.001)
    }

    func testEndingPaceUsesDistanceWhenReportedSpeedStalls() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 90, distanceMeters: 300, speedMetersPerSecond: 3.5),
            TelemetrySample(elapsed: 100, distanceMeters: 340, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 101, distanceMeters: 344, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 102, distanceMeters: 348, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 103, distanceMeters: 352, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 104, distanceMeters: 358, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 105, distanceMeters: 365, speedMetersPerSecond: 4)
        ])

        XCTAssertGreaterThan(series.sample(at: 104).speedMetersPerSecond ?? -1, series.sample(at: 103).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 105).speedMetersPerSecond ?? -1, series.sample(at: 104).speedMetersPerSecond ?? 0)
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

    func testStartupMissingSpeedDoesNotCreateImplausibleSpikeBeforeDeviceZeroes() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 100),
            TelemetrySample(elapsed: 2, distanceMeters: 100, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 3, distanceMeters: 113, speedMetersPerSecond: 2)
        ])

        XCTAssertLessThan(series.sample(at: 1).speedMetersPerSecond ?? 99, 1)
        XCTAssertLessThan(series.sample(at: 2).speedMetersPerSecond ?? 99, 1)
        XCTAssertEqual(series.sample(at: 3).speedMetersPerSecond ?? -1, 2, accuracy: 0.001)
    }

    func testStartupPaceIgnoresDeviceZeroesWhenDistanceTrendShowsMovement() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 0.8),
            TelemetrySample(elapsed: 2, distanceMeters: 1.7),
            TelemetrySample(elapsed: 3, distanceMeters: 2.7),
            TelemetrySample(elapsed: 4, distanceMeters: 2.7, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 5, distanceMeters: 2.7, speedMetersPerSecond: 0),
            TelemetrySample(
                elapsed: 6,
                latitude: 35,
                longitude: 139,
                heartRate: 140,
                cadence: 180,
                distanceMeters: 9,
                speedMetersPerSecond: 2.2
            ),
            TelemetrySample(
                elapsed: 7,
                latitude: 35.0001,
                longitude: 139.0001,
                heartRate: 142,
                cadence: 182,
                distanceMeters: 12,
                speedMetersPerSecond: 2.4
            )
        ])

        XCTAssertGreaterThan(series.sample(at: 4).speedMetersPerSecond ?? -1, series.sample(at: 3).speedMetersPerSecond ?? 0)
        XCTAssertGreaterThan(series.sample(at: 5).speedMetersPerSecond ?? -1, series.sample(at: 4).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 6).speedMetersPerSecond ?? -1, 2.2, accuracy: 0.001)
    }

    private static func catchUpStartSamples() -> [TelemetrySample] {
        // 建模自华为式设备 1000m 测速跑：距离前 5 秒冻结后猛补，速度场滞后爬升到 t=10 才进入平台
        var samples: [TelemetrySample] = [TelemetrySample(elapsed: 0, distanceMeters: 0)]
        let distances: [Double] = [0, 0, 0, 0, 9, 18, 25, 32, 39, 46, 53.5, 61]
        let speeds: [Double?] = [nil, nil, 0, 0, 2.172, 4.347, 4.733, 5.119, 5.608, 6.1, 6.119, 6.139]
        let cadences: [Int?] = [nil, nil, nil, nil, nil, nil, nil, nil, 220, 218, 216, 212]
        for index in 0..<distances.count {
            samples.append(TelemetrySample(
                elapsed: TimeInterval(index + 1),
                latitude: 34.68 + Double(index) * 0.0001,
                longitude: 135.53 + Double(index) * 0.0001,
                heartRate: 125 + index,
                cadence: cadences[index],
                distanceMeters: distances[index],
                speedMetersPerSecond: speeds[index]
            ))
        }
        return samples
    }

    func testStartupCatchUpRampReplacesLaggedDeviceSpeeds() {
        let series = TelemetrySeries(samples: Self.catchUpStartSamples())

        // 配速单调爬升，无断崖：任意相邻秒速度比值不超过跳变阈值
        var previousSpeed = series.sample(at: 0).speedMetersPerSecond ?? 0
        for second in 1...10 {
            let speed = series.sample(at: TimeInterval(second)).speedMetersPerSecond ?? -1
            XCTAssertGreaterThanOrEqual(speed, previousSpeed - 0.001, "t=\(second) 配速不应回落")
            // 站立起点到首秒的比值天然偏大，断崖检查只在进入移动后生效
            if previousSpeed > 1 {
                XCTAssertLessThan(speed / previousSpeed, 1.6, "t=\(second) 不应出现配速断崖")
            }
            previousSpeed = speed
        }
        // 稳定点及之后保留设备原始速度
        XCTAssertEqual(series.sample(at: 10).speedMetersPerSecond ?? -1, 6.1, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 11).speedMetersPerSecond ?? -1, 6.119, accuracy: 0.001)
        // 修正段在稳定点之前就应接近目标速度（旧行为 t=6 仍显示 4.347）
        XCTAssertGreaterThan(series.sample(at: 6).speedMetersPerSecond ?? -1, 5.0)
        // 稳定点实测距离锚保持不变，重排后的距离无补账跳变
        XCTAssertEqual(series.sample(at: 10).distanceMeters ?? -1, 46, accuracy: 0.001)
        var previousDistance = series.sample(at: 0).distanceMeters ?? 0
        for second in 1...10 {
            let distance = series.sample(at: TimeInterval(second)).distanceMeters ?? -1
            XCTAssertLessThan(distance - previousDistance, 7, "t=\(second) 距离不应有补账跳变")
            XCTAssertGreaterThanOrEqual(distance, previousDistance)
            previousDistance = distance
        }
    }

    func testStartupCatchUpCadenceFollowsRamp() {
        let series = TelemetrySeries(samples: Self.catchUpStartSamples())

        // 步频跟随同一条加速斜坡，t=7 应接近目标而不是线性爬升的中段值
        XCTAssertGreaterThan(series.sample(at: 7).cadence ?? -1, 200)
        XCTAssertGreaterThan(series.sample(at: 2).cadence ?? -1, 90)
        XCTAssertEqual(series.sample(at: 9).cadence ?? -1, 220)
    }

    func testStartupCatchUpDoesNotTriggerWhenDistanceMatchesSpeed() {
        // 建模自佳明式设备：速度与距离段一致，起跑无补账
        let distances: [Double] = [0, 1.69, 4.42, 6.48, 9.02, 11.75, 14.15, 16.2]
        let speeds: [Double] = [3.386, 3.386, 1.983, 1.983, 2.205, 2.298, 2.465, 2.465]
        var samples: [TelemetrySample] = []
        for index in 0..<distances.count {
            samples.append(TelemetrySample(
                elapsed: TimeInterval(index),
                latitude: 34.67 + Double(index) * 0.0001,
                longitude: 135.51 + Double(index) * 0.0001,
                heartRate: 87 + index,
                cadence: 166,
                distanceMeters: distances[index],
                speedMetersPerSecond: speeds[index]
            ))
        }
        let series = TelemetrySeries(samples: samples)

        XCTAssertNil(TelemetrySeries.startupCatchUpCorrection(in: samples))
        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 3.386, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).speedMetersPerSecond ?? -1, 1.983, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 2.298, accuracy: 0.001)
    }

    func testStartupCatchUpIsIdempotentAcrossReinitialization() {
        // FITParser 会带着 lap 锚点重新初始化 TelemetrySeries，修正不能被叠加
        let series = TelemetrySeries(samples: Self.catchUpStartSamples())
        let reinitialized = TelemetrySeries(samples: series.samples)

        for (lhs, rhs) in zip(series.samples, reinitialized.samples) {
            XCTAssertEqual(lhs.elapsed, rhs.elapsed, accuracy: 0.001)
            XCTAssertEqual(lhs.speedMetersPerSecond ?? -1, rhs.speedMetersPerSecond ?? -1, accuracy: 0.001)
            XCTAssertEqual(lhs.distanceMeters ?? -1, rhs.distanceMeters ?? -1, accuracy: 0.01)
        }
    }

    func testStartupPaceKeepsReliableDeviceSpeedBeforeCadenceStarts() {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, latitude: 35, longitude: 139, heartRate: 125, distanceMeters: 0),
            TelemetrySample(elapsed: 2, latitude: 35.0001, longitude: 139.0001, heartRate: 126, distanceMeters: 0),
            TelemetrySample(elapsed: 3, latitude: 35.0002, longitude: 139.0002, heartRate: 127, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 4, latitude: 35.0003, longitude: 139.0003, heartRate: 128, distanceMeters: 0, speedMetersPerSecond: 0),
            TelemetrySample(elapsed: 5, latitude: 35.0004, longitude: 139.0004, heartRate: 129, distanceMeters: 9, speedMetersPerSecond: 2.172),
            TelemetrySample(elapsed: 6, latitude: 35.0005, longitude: 139.0005, heartRate: 130, distanceMeters: 18, speedMetersPerSecond: 4.347),
            TelemetrySample(
                elapsed: 7,
                latitude: 35.0006,
                longitude: 139.0006,
                heartRate: 131,
                cadence: 180,
                distanceMeters: 25,
                speedMetersPerSecond: 4.733
            )
        ])

        XCTAssertLessThan(series.sample(at: 4).speedMetersPerSecond ?? 99, series.sample(at: 5).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 5).speedMetersPerSecond ?? -1, 2.172, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 6).speedMetersPerSecond ?? -1, 4.347, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 7).speedMetersPerSecond ?? -1, 4.733, accuracy: 0.001)
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
