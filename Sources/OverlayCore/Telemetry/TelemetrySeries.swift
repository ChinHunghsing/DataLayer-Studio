import Foundation

public struct GeoBounds: Equatable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double
}

public struct TelemetrySeries: Equatable {
    public private(set) var samples: [TelemetrySample]
    public let bounds: GeoBounds?
    private static let resampleInterval: TimeInterval = 1
    private static let minimumMovingSpeedMetersPerSecond = 0.3
    private static let startupRampMinimumSpeedMetersPerSecond = 0.35
    private static let startupRampSpeedRatio = 0.25
    private static let maximumPlausibleStartupSpeedMetersPerSecond = 12.0
    private static let maximumStartupPaceSmoothingElapsed: TimeInterval = 15
    private static let startupPaceSmoothingExponent = 1.7
    private static let startupSegmentConsistencyRatio = 1.6
    private static let startupSpeedJumpRatio = 1.6
    private static let startupStaleSpeedToleranceMetersPerSecond = 0.05
    private static let startupCatchUpIntegralRatio = 1.2
    private static let minimumStartupCatchUpRampDuration: TimeInterval = 2
    private static let distanceEpsilon = 0.001
    private static let minimumAscentDeltaMeters = 1.0

    public init(samples: [TelemetrySample]) {
        let sorted = samples.sorted { lhs, rhs in
            if lhs.elapsed == rhs.elapsed {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.elapsed < rhs.elapsed
        }

        let normalized = TelemetrySeries.normalized(samples: sorted)
        let startupCompleteElapsed = TelemetrySeries.firstStartupCompleteSampleElapsed(in: normalized)
        let startupCatchUp = TelemetrySeries.startupCatchUpCorrection(in: normalized)
        let speedEnriched = TelemetrySeries.enrichedWithDistanceDerivedSpeed(samples: normalized)
        let startupSpeedStabilized = TelemetrySeries.stabilizedStartupSpeedJumps(
            samples: speedEnriched,
            protectedStartElapsed: startupCompleteElapsed
        )
        let resampled = TelemetrySeries.resampled(samples: startupSpeedStabilized, interval: Self.resampleInterval)
        let startupSmoothed: [TelemetrySample]
        if let startupCatchUp {
            startupSmoothed = TelemetrySeries.appliedStartupCatchUp(samples: resampled, correction: startupCatchUp)
        } else {
            startupSmoothed = TelemetrySeries.smoothedStartupPace(
                samples: resampled,
                protectedStartElapsed: startupCompleteElapsed
            )
        }
        let edgeSmoothed = TelemetrySeries.smoothedEdgeSpeedPlateaus(
            samples: startupSmoothed,
            protectedStartElapsed: startupCompleteElapsed
        )
        let cadenceEnriched = TelemetrySeries.enrichedWithStartupCadence(
            samples: edgeSmoothed,
            interval: Self.resampleInterval,
            catchUp: startupCatchUp
        )
        let ascentEnriched = TelemetrySeries.enrichedWithTotalAscent(samples: cadenceEnriched)
        self.samples = TelemetrySeries.trimmedIncompleteTail(samples: ascentEnriched)
        self.bounds = TelemetrySeries.computeBounds(samples: self.samples)
    }

    public var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.elapsed - first.elapsed)
    }

    public var isEmpty: Bool {
        samples.isEmpty
    }

    public var activityStartDate: Date? {
        guard let datedSample = samples.first(where: { $0.date != nil }),
              let date = datedSample.date else {
            return nil
        }
        return date.addingTimeInterval(-datedSample.elapsed)
    }

    public func date(atElapsed elapsed: TimeInterval) -> Date? {
        guard elapsed.isFinite else { return nil }
        if let first = samples.first,
           elapsed < first.elapsed,
           let date = first.date {
            return date.addingTimeInterval(elapsed - first.elapsed)
        }
        if let last = samples.last,
           elapsed > last.elapsed,
           let date = last.date {
            return date.addingTimeInterval(elapsed - last.elapsed)
        }
        if let date = sample(at: elapsed).date {
            return date
        }
        guard let activityStartDate else { return nil }
        return activityStartDate.addingTimeInterval(elapsed)
    }

    public func sample(at elapsed: TimeInterval) -> TelemetrySample {
        guard let first = samples.first else {
            return TelemetrySample(elapsed: elapsed)
        }
        guard samples.count > 1 else {
            return first
        }
        if elapsed <= first.elapsed {
            return first
        }
        if elapsed >= samples[samples.count - 1].elapsed {
            return samples[samples.count - 1]
        }

        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].elapsed <= elapsed {
                low = mid
            } else {
                high = mid
            }
        }

        let a = samples[low]
        let b = samples[high]
        let span = max(b.elapsed - a.elapsed, 0.000_001)
        let fraction = min(1, max(0, (elapsed - a.elapsed) / span))
        return interpolate(a, b, fraction: fraction, elapsed: elapsed)
    }

    public func trimmed(by trim: ActivityTrim) -> TelemetrySeries {
        guard !samples.isEmpty else { return self }
        let sourceDuration = duration
        guard trim.isActive(for: sourceDuration) else { return self }

        let trimStart = trim.start(in: sourceDuration)
        let trimEnd = trim.end(in: sourceDuration)
        let startSample = sample(at: trimStart)
        let endSample = sample(at: trimEnd)
        let distanceOffset = startSample.distanceMeters
        let calorieOffset = startSample.totalCalories
        let ascentOffset = startSample.totalAscentMeters

        var trimmedSamples: [TelemetrySample] = [
            rebasedSample(
                startSample,
                trimStart: trimStart,
                distanceOffset: distanceOffset,
                calorieOffset: calorieOffset,
                ascentOffset: ascentOffset
            )
        ]

        for sample in samples where sample.elapsed > trimStart && sample.elapsed < trimEnd {
            trimmedSamples.append(
                rebasedSample(
                    sample,
                    trimStart: trimStart,
                    distanceOffset: distanceOffset,
                    calorieOffset: calorieOffset,
                    ascentOffset: ascentOffset
                )
            )
        }

        if trimEnd > trimStart {
            let rebasedEnd = rebasedSample(
                endSample,
                trimStart: trimStart,
                distanceOffset: distanceOffset,
                calorieOffset: calorieOffset,
                ascentOffset: ascentOffset
            )
            if trimmedSamples.last?.elapsed != rebasedEnd.elapsed {
                trimmedSamples.append(rebasedEnd)
            }
        }

        return TelemetrySeries(samples: trimmedSamples)
    }

    private func interpolate(
        _ a: TelemetrySample,
        _ b: TelemetrySample,
        fraction: Double,
        elapsed: TimeInterval
    ) -> TelemetrySample {
        Self.interpolate(a, b, fraction: fraction, elapsed: elapsed)
    }

    private func rebasedSample(
        _ sample: TelemetrySample,
        trimStart: TimeInterval,
        distanceOffset: Double?,
        calorieOffset: Double?,
        ascentOffset: Double?
    ) -> TelemetrySample {
        var output = sample
        output.elapsed = max(0, sample.elapsed - trimStart)
        if let distance = sample.distanceMeters, let distanceOffset {
            output.distanceMeters = max(0, distance - distanceOffset)
        }
        if let calories = sample.totalCalories, let calorieOffset {
            output.totalCalories = max(0, calories - calorieOffset)
        }
        if let ascent = sample.totalAscentMeters, let ascentOffset {
            output.totalAscentMeters = max(0, ascent - ascentOffset)
        }
        return output
    }

    private static func interpolate(
        _ a: TelemetrySample,
        _ b: TelemetrySample,
        fraction: Double,
        elapsed: TimeInterval
    ) -> TelemetrySample {
        TelemetrySample(
            elapsed: elapsed,
            date: interpolatedDate(a.date, b.date, fraction: fraction),
            latitude: interpolate(a.latitude, b.latitude, fraction: fraction),
            longitude: interpolate(a.longitude, b.longitude, fraction: fraction),
            altitudeMeters: interpolate(a.altitudeMeters, b.altitudeMeters, fraction: fraction),
            totalAscentMeters: interpolate(a.totalAscentMeters, b.totalAscentMeters, fraction: fraction),
            heartRate: nearest(a.heartRate, b.heartRate, fraction: fraction),
            cadence: interpolateCadence(a.cadence, b.cadence, fraction: fraction),
            distanceMeters: interpolate(a.distanceMeters, b.distanceMeters, fraction: fraction),
            speedMetersPerSecond: interpolate(a.speedMetersPerSecond, b.speedMetersPerSecond, fraction: fraction),
            powerWatts: nearest(a.powerWatts, b.powerWatts, fraction: fraction),
            verticalOscillationCentimeters: interpolate(a.verticalOscillationCentimeters, b.verticalOscillationCentimeters, fraction: fraction),
            groundContactTimeMilliseconds: interpolate(a.groundContactTimeMilliseconds, b.groundContactTimeMilliseconds, fraction: fraction),
            groundContactTimePercent: interpolate(a.groundContactTimePercent, b.groundContactTimePercent, fraction: fraction),
            groundContactTimeBalancePercent: interpolate(a.groundContactTimeBalancePercent, b.groundContactTimeBalancePercent, fraction: fraction),
            verticalRatioPercent: interpolate(a.verticalRatioPercent, b.verticalRatioPercent, fraction: fraction),
            respirationRateBreathsPerMinute: interpolate(a.respirationRateBreathsPerMinute, b.respirationRateBreathsPerMinute, fraction: fraction),
            stepSpeedLossPercent: interpolate(a.stepSpeedLossPercent, b.stepSpeedLossPercent, fraction: fraction),
            formPowerWatts: nearest(a.formPowerWatts, b.formPowerWatts, fraction: fraction),
            airPowerWatts: nearest(a.airPowerWatts, b.airPowerWatts, fraction: fraction),
            legSpringStiffnessKilonewtonsPerMeter: interpolate(a.legSpringStiffnessKilonewtonsPerMeter, b.legSpringStiffnessKilonewtonsPerMeter, fraction: fraction),
            totalCalories: interpolate(a.totalCalories, b.totalCalories, fraction: fraction),
            stepLengthMeters: interpolate(a.stepLengthMeters, b.stepLengthMeters, fraction: fraction),
            temperatureCelsius: nearest(a.temperatureCelsius, b.temperatureCelsius, fraction: fraction),
            weatherTemperatureCelsius: nearest(a.weatherTemperatureCelsius, b.weatherTemperatureCelsius, fraction: fraction),
            weatherHumidityPercent: nearest(a.weatherHumidityPercent, b.weatherHumidityPercent, fraction: fraction),
            weatherSummary: nearest(a.weatherSummary, b.weatherSummary, fraction: fraction)
        )
    }

    private static func interpolate(_ a: Double?, _ b: Double?, fraction: Double) -> Double? {
        switch (a, b) {
        case let (.some(lhs), .some(rhs)):
            return lhs + ((rhs - lhs) * fraction)
        case let (.some(value), .none):
            return value
        case let (.none, .some(value)):
            return value
        case (.none, .none):
            return nil
        }
    }

    private static func nearest(_ a: Int?, _ b: Int?, fraction: Double) -> Int? {
        fraction < 0.5 ? (a ?? b) : (b ?? a)
    }

    private static func nearest(_ a: String?, _ b: String?, fraction: Double) -> String? {
        fraction < 0.5 ? (a ?? b) : (b ?? a)
    }

    private static func interpolateCadence(_ a: Int?, _ b: Int?, fraction: Double) -> Int? {
        guard let lhs = a, let rhs = b else { return nil }
        guard lhs == 0 || rhs == 0 else {
            return nearest(a, b, fraction: fraction)
        }
        let value = Double(lhs) + (Double(rhs - lhs) * fraction)
        return max(0, Int(value.rounded()))
    }

    private static func interpolatedDate(_ a: Date?, _ b: Date?, fraction: Double) -> Date? {
        guard let a, let b else { return a ?? b }
        return a.addingTimeInterval(b.timeIntervalSince(a) * fraction)
    }

    private static func normalized(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard !samples.isEmpty else { return [] }

        let firstDistance = startupDistanceBaseline(samples: samples)
        let firstElapsed = samples.first?.elapsed ?? 0
        var previousInput: TelemetrySample?
        var previousOutput: TelemetrySample?
        var hasSeenReportedMovingSpeed = false
        var accumulatedDistance = 0.0
        var output: [TelemetrySample] = []

        for input in samples {
            var sample = input
            if let reportedSpeed = input.speedMetersPerSecond,
               reportedSpeed.isFinite,
               reportedSpeed >= minimumMovingSpeedMetersPerSecond {
                hasSeenReportedMovingSpeed = true
            }

            if let distance = input.distanceMeters {
                accumulatedDistance = max(accumulatedDistance, max(0, distance - firstDistance))
            } else if
                let previousInput,
                let prevLat = previousInput.latitude,
                let prevLon = previousInput.longitude,
                let lat = input.latitude,
                let lon = input.longitude
            {
                accumulatedDistance += haversineMeters(
                    latitude1: prevLat,
                    longitude1: prevLon,
                    latitude2: lat,
                    longitude2: lon
                )
            }

            sample.distanceMeters = accumulatedDistance

            if sample.speedMetersPerSecond == nil {
                if !hasSeenReportedMovingSpeed,
                   input.elapsed - firstElapsed <= maximumStartupPaceSmoothingElapsed {
                    sample.speedMetersPerSecond = 0
                } else if let previousOutput,
                          input.elapsed > previousOutput.elapsed {
                    let deltaDistance = accumulatedDistance - (previousOutput.distanceMeters ?? accumulatedDistance)
                    let deltaTime = input.elapsed - previousOutput.elapsed
                    if deltaDistance >= 0, deltaTime > 0 {
                        sample.speedMetersPerSecond = deltaDistance / deltaTime
                    }
                }
            }

            output.append(sample)
            previousInput = input
            previousOutput = sample
        }

        return backfilledStartupDistances(samples: output, baseline: firstDistance)
    }

    private static func startupDistanceBaseline(samples: [TelemetrySample]) -> Double {
        guard let first = samples.first else { return 0 }
        guard let firstDistance = samples.compactMap(\.distanceMeters).first else { return 0 }
        guard first.distanceMeters == nil,
              let firstDistanceSample = samples.first(where: { $0.distanceMeters != nil }),
              firstDistanceSample.elapsed > first.elapsed else {
            return firstDistance
        }

        let elapsed = firstDistanceSample.elapsed - first.elapsed
        let startupSpeed = firstDistance / elapsed
        return startupSpeed <= maximumPlausibleStartupSpeedMetersPerSecond ? 0 : firstDistance
    }

    private static func backfilledStartupDistances(
        samples: [TelemetrySample],
        baseline: Double
    ) -> [TelemetrySample] {
        guard baseline <= distanceEpsilon,
              samples.count > 1,
              let first = samples.first,
              let targetIndex = samples.firstIndex(where: { ($0.distanceMeters ?? 0) > distanceEpsilon }),
              targetIndex > 0 else {
            return samples
        }

        let target = samples[targetIndex]
        guard let targetDistance = target.distanceMeters,
              targetDistance.isFinite else {
            return samples
        }

        let elapsed = target.elapsed - first.elapsed
        guard elapsed > 0 else { return samples }
        let startupSpeed = targetDistance / elapsed
        guard startupSpeed.isFinite,
              startupSpeed <= maximumPlausibleStartupSpeedMetersPerSecond else {
            return samples
        }

        guard samples[..<targetIndex].allSatisfy({ ($0.distanceMeters ?? 0) <= distanceEpsilon }) else {
            return samples
        }

        var output = samples
        for index in 0..<targetIndex {
            let sampleElapsed = samples[index].elapsed - first.elapsed
            guard sampleElapsed > 0 else {
                output[index].distanceMeters = 0
                continue
            }

            let progress = min(1, max(0, sampleElapsed / elapsed))
            output[index].distanceMeters = targetDistance * progress
        }
        return output
    }

    private static func enrichedWithDistanceDerivedSpeed(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.count > 1 else { return samples }

        let firstElapsed = samples.first?.elapsed ?? 0
        var output = samples
        for index in 0..<(samples.count - 1) {
            let current = output[index]
            let next = output[index + 1]
            guard let currentDistance = current.distanceMeters,
                  let nextDistance = next.distanceMeters else {
                continue
            }

            let deltaTime = next.elapsed - current.elapsed
            let deltaDistance = nextDistance - currentDistance
            guard deltaTime > 0, deltaDistance > 0 else { continue }

            let segmentSpeed = deltaDistance / deltaTime
            guard segmentSpeed >= minimumMovingSpeedMetersPerSecond else { continue }
            guard current.elapsed - firstElapsed > maximumStartupPaceSmoothingElapsed ||
                  segmentSpeed <= maximumPlausibleStartupSpeedMetersPerSecond else {
                continue
            }

            if shouldReplaceSpeed(output[index].speedMetersPerSecond) {
                output[index].speedMetersPerSecond = speedForSegmentStart(
                    index: index,
                    current: current,
                    segmentSpeed: segmentSpeed
                )
            }
            if shouldReplaceSpeed(output[index + 1].speedMetersPerSecond) {
                output[index + 1].speedMetersPerSecond = segmentSpeed
            }
        }

        return output
    }

    private static func enrichedWithTotalAscent(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.contains(where: { $0.altitudeMeters?.isFinite == true }) else {
            return samples
        }

        var referenceAltitude: Double?
        var totalAscent = 0.0
        return samples.map { input in
            var sample = input
            guard let altitude = input.altitudeMeters, altitude.isFinite else {
                sample.totalAscentMeters = totalAscent
                return sample
            }

            if let baselineAltitude = referenceAltitude {
                let delta = altitude - baselineAltitude
                if delta >= minimumAscentDeltaMeters {
                    totalAscent += delta
                    referenceAltitude = altitude
                } else if delta < 0 {
                    referenceAltitude = altitude
                }
            } else {
                referenceAltitude = altitude
            }
            sample.totalAscentMeters = totalAscent
            return sample
        }
    }

    private static func shouldReplaceSpeed(_ speed: Double?) -> Bool {
        guard let speed, speed.isFinite else { return true }
        return speed < minimumMovingSpeedMetersPerSecond
    }

    private static func speedForSegmentStart(
        index: Int,
        current: TelemetrySample,
        segmentSpeed: Double
    ) -> Double {
        guard index == 0, current.elapsed <= 0.000_001 else {
            return segmentSpeed
        }

        return min(
            segmentSpeed,
            max(startupRampMinimumSpeedMetersPerSecond, segmentSpeed * startupRampSpeedRatio)
        )
    }

    private static func stabilizedStartupSpeedJumps(
        samples: [TelemetrySample],
        protectedStartElapsed: TimeInterval?
    ) -> [TelemetrySample] {
        guard samples.count > 2 else { return samples }

        var output = samples
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let current = samples[index]
            let next = samples[index + 1]
            if let protectedStartElapsed, current.elapsed >= protectedStartElapsed {
                break
            }
            guard current.elapsed <= maximumStartupPaceSmoothingElapsed,
                  let currentSpeed = current.speedMetersPerSecond,
                  currentSpeed.isFinite,
                  let previousDistance = previous.distanceMeters,
                  let currentDistance = current.distanceMeters,
                  let nextDistance = next.distanceMeters else {
                continue
            }

            let previousSpan = current.elapsed - previous.elapsed
            let nextSpan = next.elapsed - current.elapsed
            guard previousSpan > 0,
                  nextSpan > 0 else {
                continue
            }

            let previousSpeed = (currentDistance - previousDistance) / previousSpan
            let nextSpeed = (nextDistance - currentDistance) / nextSpan
            guard previousSpeed >= minimumMovingSpeedMetersPerSecond,
                  nextSpeed >= minimumMovingSpeedMetersPerSecond else {
                continue
            }

            let lowSegmentSpeed = min(previousSpeed, nextSpeed)
            let highSegmentSpeed = max(previousSpeed, nextSpeed)
            guard highSegmentSpeed / lowSegmentSpeed <= startupSegmentConsistencyRatio else {
                continue
            }

            let distanceSpeed = (previousSpeed + nextSpeed) / 2
            guard distanceSpeed <= maximumPlausibleStartupSpeedMetersPerSecond else {
                continue
            }

            let speedRatio = max(currentSpeed, distanceSpeed) / max(min(currentSpeed, distanceSpeed), 0.000_001)
            if speedRatio >= startupSpeedJumpRatio {
                output[index].speedMetersPerSecond = distanceSpeed
            }
        }
        return output
    }

    private static func enrichedWithStartupCadence(
        samples: [TelemetrySample],
        interval: TimeInterval,
        catchUp: StartupCatchUpCorrection? = nil
    ) -> [TelemetrySample] {
        guard samples.count > 1,
              interval > 0,
              let first = samples.first,
              let targetIndex = samples.firstIndex(where: { ($0.cadence ?? 0) > 0 }),
              targetIndex > 0 else {
            return samples
        }

        let target = samples[targetIndex]
        guard let targetCadence = target.cadence,
              targetCadence > 0,
              target.elapsed > first.elapsed else {
            return samples
        }
        guard samples[..<targetIndex].allSatisfy({ ($0.cadence ?? 0) <= 0 }) else {
            return samples
        }

        var output = samples
        for index in 0..<targetIndex {
            output[index].cadence = startupCadence(
                at: output[index].elapsed,
                firstElapsed: first.elapsed,
                targetElapsed: target.elapsed,
                targetCadence: targetCadence,
                catchUp: catchUp
            )
        }

        var elapsed = first.elapsed + interval
        while elapsed < target.elapsed {
            if !output.contains(where: { abs($0.elapsed - elapsed) < 0.000_001 }) {
                var sample = interpolatedSample(samples: samples, elapsed: elapsed)
                sample.cadence = startupCadence(
                    at: elapsed,
                    firstElapsed: first.elapsed,
                    targetElapsed: target.elapsed,
                    targetCadence: targetCadence,
                    catchUp: catchUp
                )
                output.append(sample)
            }
            elapsed += interval
        }

        return output.sorted { lhs, rhs in
            if lhs.elapsed == rhs.elapsed {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.elapsed < rhs.elapsed
        }
    }

    private static func startupCadence(
        at elapsed: TimeInterval,
        firstElapsed: TimeInterval,
        targetElapsed: TimeInterval,
        targetCadence: Int,
        catchUp: StartupCatchUpCorrection? = nil
    ) -> Int {
        if let catchUp {
            let progress = min(1, max(0, (elapsed - firstElapsed) / catchUp.rampDuration))
            let eased = pow(progress, 1 / startupPaceSmoothingExponent)
            return max(0, Int((Double(targetCadence) * eased).rounded()))
        }
        let span = max(targetElapsed - firstElapsed, 0.000_001)
        let progress = min(1, max(0, (elapsed - firstElapsed) / span))
        return max(0, Int((Double(targetCadence) * progress).rounded()))
    }

    private static func interpolatedSample(samples: [TelemetrySample], elapsed: TimeInterval) -> TelemetrySample {
        guard let first = samples.first else { return TelemetrySample(elapsed: elapsed) }
        guard let last = samples.last else { return first }
        guard elapsed > first.elapsed else { return first }
        guard elapsed < last.elapsed else { return last }

        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].elapsed <= elapsed {
                low = mid
            } else {
                high = mid
            }
        }

        let a = samples[low]
        let b = samples[high]
        let span = max(b.elapsed - a.elapsed, 0.000_001)
        let fraction = min(1, max(0, (elapsed - a.elapsed) / span))
        return interpolate(a, b, fraction: fraction, elapsed: elapsed)
    }

    struct StartupCatchUpCorrection {
        var stabilizationElapsed: TimeInterval
        var targetSpeed: Double
        var rampDuration: TimeInterval
    }

    /// 检测起跑“距离补账”签名：设备距离先冻结再猛补，速度场滞后爬升。
    /// 四个条件同时成立才触发：速度进入平台、单调爬升达到跳变比、
    /// 距离段速度大幅超过同秒设备速度、累计距离明显超过设备速度积分。
    static func startupCatchUpCorrection(in samples: [TelemetrySample]) -> StartupCatchUpCorrection? {
        guard samples.count > 3, let first = samples.first else { return nil }
        let firstElapsed = first.elapsed

        func movingSpeed(at index: Int) -> Double? {
            guard let value = samples[index].speedMetersPerSecond,
                  value.isFinite,
                  value >= minimumMovingSpeedMetersPerSecond else {
                return nil
            }
            return value
        }

        guard let movingIndex = samples.indices.first(where: { index in
            samples[index].elapsed - firstElapsed <= maximumStartupPaceSmoothingElapsed
                && movingSpeed(at: index) != nil
        }) else { return nil }

        var stabilizationIndex: Int?
        var index = movingIndex + 1
        while index + 2 < samples.count,
              samples[index].elapsed - firstElapsed <= maximumStartupPaceSmoothingElapsed {
            if let current = movingSpeed(at: index),
               let next = movingSpeed(at: index + 1),
               let afterNext = movingSpeed(at: index + 2),
               abs(next - current) <= startupStaleSpeedToleranceMetersPerSecond,
               abs(afterNext - next) <= startupStaleSpeedToleranceMetersPerSecond {
                stabilizationIndex = index
                break
            }
            index += 1
        }
        guard let stabilizationIndex,
              let targetSpeed = plausibleSpeed(samples[stabilizationIndex].speedMetersPerSecond),
              let firstMovingSpeed = movingSpeed(at: movingIndex) else {
            return nil
        }
        let stabilizationElapsed = samples[stabilizationIndex].elapsed - firstElapsed
        guard stabilizationElapsed > 0,
              targetSpeed / firstMovingSpeed >= startupSpeedJumpRatio else {
            return nil
        }

        var previousSpeed = firstMovingSpeed
        for index in (movingIndex + 1)...stabilizationIndex {
            guard let speed = movingSpeed(at: index) else { continue }
            guard speed >= previousSpeed - startupStaleSpeedToleranceMetersPerSecond else { return nil }
            previousSpeed = speed
        }

        // 段速度只作为“距离在补账”的证据，不设合理速度上限
        var distanceRunsAhead = false
        for index in max(movingIndex, 1)...stabilizationIndex {
            guard let speed = movingSpeed(at: index),
                  let previousDistance = samples[index - 1].distanceMeters,
                  let distance = samples[index].distanceMeters else {
                continue
            }
            let deltaTime = samples[index].elapsed - samples[index - 1].elapsed
            guard deltaTime > 0 else { continue }
            if (distance - previousDistance) / deltaTime >= startupSpeedJumpRatio * speed {
                distanceRunsAhead = true
                break
            }
        }
        guard distanceRunsAhead else { return nil }

        guard let anchorDistance = samples[stabilizationIndex].distanceMeters else { return nil }
        let coveredDistance = anchorDistance - (first.distanceMeters ?? 0)
        guard coveredDistance > distanceEpsilon else { return nil }
        var speedIntegral = 0.0
        for index in 1...stabilizationIndex {
            let deltaTime = samples[index].elapsed - samples[index - 1].elapsed
            guard deltaTime > 0 else { continue }
            let previous = samples[index - 1].speedMetersPerSecond ?? 0
            let current = samples[index].speedMetersPerSecond ?? 0
            speedIntegral += (max(previous.isFinite ? previous : 0, 0) + max(current.isFinite ? current : 0, 0)) / 2 * deltaTime
        }
        guard coveredDistance > startupCatchUpIntegralRatio * speedIntegral else { return nil }

        // 斜坡时长由“修正后速度积分 ≈ 稳定点实测距离”解出，保证配速与里程自洽
        let exponent = 1 / startupPaceSmoothingExponent
        let baseSpeed = startupRampMinimumSpeedMetersPerSecond
        let coefficient = (targetSpeed - baseSpeed) * (1 - 1 / (exponent + 1))
        guard coefficient > 0 else { return nil }
        let rawDuration = (targetSpeed * stabilizationElapsed - coveredDistance) / coefficient
        let rampDuration = min(max(rawDuration, minimumStartupCatchUpRampDuration), stabilizationElapsed)

        return StartupCatchUpCorrection(
            stabilizationElapsed: stabilizationElapsed,
            targetSpeed: targetSpeed,
            rampDuration: rampDuration
        )
    }

    private static func appliedStartupCatchUp(
        samples: [TelemetrySample],
        correction: StartupCatchUpCorrection
    ) -> [TelemetrySample] {
        guard let first = samples.first else { return samples }
        let firstElapsed = first.elapsed
        let baseSpeed = startupRampMinimumSpeedMetersPerSecond
        let exponent = 1 / startupPaceSmoothingExponent

        func rampSpeed(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 else { return baseSpeed }
            guard elapsed < correction.rampDuration else { return correction.targetSpeed }
            let progress = pow(elapsed / correction.rampDuration, exponent)
            return baseSpeed + (correction.targetSpeed - baseSpeed) * progress
        }

        var output = samples
        var lastCorrectedIndex: Int?
        for index in samples.indices {
            let elapsed = samples[index].elapsed - firstElapsed
            guard elapsed < correction.stabilizationElapsed - 0.000_001 else { break }
            output[index].speedMetersPerSecond = rampSpeed(at: elapsed)
            lastCorrectedIndex = index
        }
        guard let lastCorrectedIndex, lastCorrectedIndex + 1 < output.count else { return output }

        // 距离按修正后的速度积分重排并缩放，稳定点及之后的实测距离保持不变
        let anchorIndex = lastCorrectedIndex + 1
        let startDistance = first.distanceMeters ?? 0
        guard let anchorDistance = output[anchorIndex].distanceMeters else { return output }
        let coveredDistance = anchorDistance - startDistance
        guard coveredDistance > distanceEpsilon else { return output }

        var integrals = [Double](repeating: 0, count: anchorIndex + 1)
        for index in 1...anchorIndex {
            let deltaTime = output[index].elapsed - output[index - 1].elapsed
            guard deltaTime > 0 else {
                integrals[index] = integrals[index - 1]
                continue
            }
            let previous = output[index - 1].speedMetersPerSecond ?? baseSpeed
            let current = output[index].speedMetersPerSecond ?? correction.targetSpeed
            integrals[index] = integrals[index - 1] + (previous + current) / 2 * deltaTime
        }
        let total = integrals[anchorIndex]
        guard total > distanceEpsilon else { return output }
        let scale = coveredDistance / total
        for index in 0...lastCorrectedIndex {
            output[index].distanceMeters = startDistance + integrals[index] * scale
        }
        return output
    }

    private static func smoothedStartupPace(
        samples: [TelemetrySample],
        protectedStartElapsed: TimeInterval?
    ) -> [TelemetrySample] {
        guard samples.count > 1,
              let first = samples.first,
              (first.distanceMeters ?? 0) <= distanceEpsilon else {
            return samples
        }
        let protectedStartIndex = protectedStartIndex(in: samples, elapsed: protectedStartElapsed)
        guard protectedStartIndex > 0,
              shouldApplyStartupCumulativeSmoothing(
                  samples: samples,
                  firstElapsed: first.elapsed,
                  protectedStartIndex: protectedStartIndex
              ) else {
            return samples
        }

        var output = samples
        var lastStartupSpeed: Double?
        var firstStartupSpeed: Double?
        var firstStartupIndex: Int?
        let firstElapsed = first.elapsed

        for index in samples.indices where index < protectedStartIndex {
            let sample = samples[index]
            let elapsed = sample.elapsed - firstElapsed
            guard elapsed > 0,
                  elapsed <= maximumStartupPaceSmoothingElapsed,
                  let distance = sample.distanceMeters,
                  distance > distanceEpsilon else {
                continue
            }

            let cumulativeSpeed = distance / elapsed
            guard cumulativeSpeed.isFinite,
                  cumulativeSpeed >= minimumMovingSpeedMetersPerSecond,
                  cumulativeSpeed <= maximumPlausibleStartupSpeedMetersPerSecond else {
                continue
            }

            let smoothedSpeed = max(lastStartupSpeed ?? startupRampMinimumSpeedMetersPerSecond, cumulativeSpeed)
            output[index].speedMetersPerSecond = smoothedSpeed
            lastStartupSpeed = smoothedSpeed
            if firstStartupSpeed == nil {
                firstStartupSpeed = smoothedSpeed
                firstStartupIndex = index
            }
        }

        if let firstStartupSpeed {
            let startSpeed = min(
                firstStartupSpeed,
                max(startupRampMinimumSpeedMetersPerSecond, firstStartupSpeed * startupRampSpeedRatio)
            )
            output[0].speedMetersPerSecond = startSpeed
            if let firstStartupIndex, firstStartupIndex > 0 {
                let targetElapsed = max(samples[firstStartupIndex].elapsed - firstElapsed, 0.000_001)
                for index in 1..<firstStartupIndex {
                    let elapsed = samples[index].elapsed - firstElapsed
                    let progress = min(1, max(0, elapsed / targetElapsed))
                    let easedProgress = pow(progress, startupPaceSmoothingExponent)
                    output[index].speedMetersPerSecond = startSpeed + ((firstStartupSpeed - startSpeed) * easedProgress)
                }
            }
        }
        return output
    }

    private static func firstStartupCompleteSampleElapsed(in samples: [TelemetrySample]) -> TimeInterval? {
        guard let index = firstStartupCompleteSampleIndex(in: samples) else { return nil }
        return samples[index].elapsed
    }

    private static func shouldApplyStartupCumulativeSmoothing(
        samples: [TelemetrySample],
        firstElapsed: TimeInterval,
        protectedStartIndex: Int
    ) -> Bool {
        if shouldReplaceSpeed(samples.first?.speedMetersPerSecond) {
            return true
        }
        if earlyStartupSpeedDiffersFromCompletePoint(samples: samples, protectedStartIndex: protectedStartIndex) {
            return true
        }
        if let firstSpeed = samples.first?.speedMetersPerSecond,
           firstSpeed <= startupRampMinimumSpeedMetersPerSecond * 2 {
            for sample in samples.prefix(protectedStartIndex) {
                let elapsed = sample.elapsed - firstElapsed
                guard elapsed > 0,
                      elapsed <= maximumStartupPaceSmoothingElapsed,
                      let distance = sample.distanceMeters,
                      distance > distanceEpsilon,
                      let speed = sample.speedMetersPerSecond,
                      speed.isFinite else {
                    continue
                }

                let cumulativeSpeed = distance / elapsed
                guard cumulativeSpeed.isFinite,
                      cumulativeSpeed >= minimumMovingSpeedMetersPerSecond else {
                    continue
                }
                if speed / cumulativeSpeed >= 2 {
                    return true
                }
            }
        }
        return hasStaleStartupSpeedPlateau(
            samples: samples,
            firstElapsed: firstElapsed,
            protectedStartIndex: protectedStartIndex
        )
    }

    private static func firstStartupCompleteSampleIndex(in samples: [TelemetrySample]) -> Int? {
        samples.firstIndex { sample in
            guard let latitude = sample.latitude, latitude.isFinite,
                  let longitude = sample.longitude, longitude.isFinite,
                  plausibleSpeed(sample.speedMetersPerSecond) != nil,
                  (sample.heartRate ?? 0) > 0 else {
                return false
            }
            return true
        }
    }

    private static func earlyStartupSpeedDiffersFromCompletePoint(
        samples: [TelemetrySample],
        protectedStartIndex: Int
    ) -> Bool {
        guard protectedStartIndex < samples.count,
              let targetSpeed = plausibleSpeed(samples[protectedStartIndex].speedMetersPerSecond) else {
            return false
        }

        for index in 0..<min(3, protectedStartIndex) {
            guard let speed = plausibleSpeed(samples[index].speedMetersPerSecond) else { continue }
            let ratio = max(speed, targetSpeed) / max(min(speed, targetSpeed), 0.000_001)
            if ratio >= startupSpeedJumpRatio {
                return true
            }
        }
        return false
    }

    private static func hasStaleStartupSpeedPlateau(
        samples: [TelemetrySample],
        firstElapsed: TimeInterval,
        protectedStartIndex: Int
    ) -> Bool {
        var previousSpeed: Double?
        var previousCumulativeSpeed: Double?

        for sample in samples.prefix(protectedStartIndex) {
            let elapsed = sample.elapsed - firstElapsed
            guard elapsed > 0,
                  elapsed <= maximumStartupPaceSmoothingElapsed,
                  let distance = sample.distanceMeters,
                  distance > distanceEpsilon,
                  let speed = sample.speedMetersPerSecond,
                  speed.isFinite else {
                continue
            }

            let cumulativeSpeed = distance / elapsed
            guard cumulativeSpeed.isFinite,
                  cumulativeSpeed >= minimumMovingSpeedMetersPerSecond else {
                continue
            }

            if let previousSpeed,
               let previousCumulativeSpeed,
               abs(speed - previousSpeed) <= startupStaleSpeedToleranceMetersPerSecond,
               cumulativeSpeed > previousCumulativeSpeed + startupStaleSpeedToleranceMetersPerSecond {
                return true
            }

            previousSpeed = speed
            previousCumulativeSpeed = cumulativeSpeed
        }

        return false
    }

    private static func smoothedEdgeSpeedPlateaus(
        samples: [TelemetrySample],
        protectedStartElapsed: TimeInterval?
    ) -> [TelemetrySample] {
        guard samples.count > 2 else { return samples }
        let protectedStartIndex = protectedStartIndex(in: samples, elapsed: protectedStartElapsed)
        return smoothedTrailingSpeedPlateau(
            samples: smoothedLeadingSpeedPlateaus(samples: samples, protectedStartIndex: protectedStartIndex)
        )
    }

    private static func protectedStartIndex(in samples: [TelemetrySample], elapsed: TimeInterval?) -> Int {
        guard let elapsed else {
            return firstStartupCompleteSampleIndex(in: samples) ?? samples.count
        }
        return samples.firstIndex { $0.elapsed >= elapsed } ?? samples.count
    }

    private static func smoothedLeadingSpeedPlateaus(samples: [TelemetrySample], protectedStartIndex: Int) -> [TelemetrySample] {
        guard let firstElapsed = samples.first?.elapsed else { return samples }

        var output = samples
        var index = 0
        while index < min(protectedStartIndex, output.count - 1) {
            if output[index].elapsed - firstElapsed > maximumStartupPaceSmoothingElapsed {
                break
            }
            guard let runSpeed = output[index].speedMetersPerSecond, runSpeed.isFinite else {
                index += 1
                continue
            }

            var end = index
            while end + 1 < protectedStartIndex,
                  output[end + 1].elapsed - firstElapsed <= maximumStartupPaceSmoothingElapsed,
                  let nextRunSpeed = output[end + 1].speedMetersPerSecond,
                  nextRunSpeed.isFinite,
                  abs(nextRunSpeed - runSpeed) <= startupStaleSpeedToleranceMetersPerSecond {
                end += 1
            }

            defer { index = max(end + 1, index + 1) }
            guard end > index,
                  end + 1 < output.count,
                  let nextSpeed = output[end + 1].speedMetersPerSecond,
                  nextSpeed.isFinite,
                  nextSpeed > runSpeed + startupStaleSpeedToleranceMetersPerSecond else {
                continue
            }

            let targetCandidate: Double
            if end + 1 >= protectedStartIndex {
                targetCandidate = nextSpeed
            } else {
                targetCandidate = max(nextSpeed, distanceSpeed(samples: output, from: index, to: end + 1) ?? nextSpeed)
            }
            guard let targetSpeed = plausibleSpeed(targetCandidate) else {
                continue
            }

            let replaceEnd = min(end, protectedStartIndex - 1)
            guard replaceEnd >= index + 1 else { continue }
            output = interpolateSpeeds(
                samples: output,
                from: index,
                to: end + 1,
                targetSpeed: targetSpeed,
                replacing: (index + 1)...replaceEnd
            )
        }

        return output
    }

    private static func smoothedTrailingSpeedPlateau(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.count > 2,
              let last = samples.last,
              let first = samples.first,
              last.elapsed - first.elapsed > maximumStartupPaceSmoothingElapsed,
              let lastSpeed = last.speedMetersPerSecond,
              lastSpeed.isFinite else {
            return samples
        }

        var start = samples.count - 1
        while start > 0,
              last.elapsed - samples[start - 1].elapsed <= maximumStartupPaceSmoothingElapsed,
              let speed = samples[start - 1].speedMetersPerSecond,
              speed.isFinite,
              abs(speed - lastSpeed) <= startupStaleSpeedToleranceMetersPerSecond {
            start -= 1
        }

        guard start < samples.count - 1,
              start > 0,
              let targetSpeed = plausibleSpeed(distanceSpeed(samples: samples, from: start - 1, to: samples.count - 1)) else {
            return samples
        }
        guard abs(targetSpeed - lastSpeed) > startupStaleSpeedToleranceMetersPerSecond else {
            return samples
        }

        return interpolateSpeeds(
            samples: samples,
            from: start - 1,
            to: samples.count - 1,
            targetSpeed: targetSpeed,
            replacing: start...(samples.count - 1)
        )
    }

    private static func interpolateSpeeds(
        samples: [TelemetrySample],
        from start: Int,
        to target: Int,
        targetSpeed: Double,
        replacing range: ClosedRange<Int>
    ) -> [TelemetrySample] {
        guard start >= 0,
              target < samples.count,
              start < target,
              let startSpeed = samples[start].speedMetersPerSecond,
              startSpeed.isFinite else {
            return samples
        }

        let startElapsed = samples[start].elapsed
        let span = max(samples[target].elapsed - startElapsed, 0.000_001)
        var output = samples
        for index in range where index > start && index < output.count {
            let progress = min(1, max(0, (samples[index].elapsed - startElapsed) / span))
            let easedProgress = pow(progress, startupPaceSmoothingExponent)
            output[index].speedMetersPerSecond = startSpeed + ((targetSpeed - startSpeed) * easedProgress)
        }
        return output
    }

    private static func distanceSpeed(samples: [TelemetrySample], from start: Int, to end: Int) -> Double? {
        guard start >= 0,
              end < samples.count,
              start < end,
              let startDistance = samples[start].distanceMeters,
              let endDistance = samples[end].distanceMeters else {
            return nil
        }

        let elapsed = samples[end].elapsed - samples[start].elapsed
        let distance = endDistance - startDistance
        guard elapsed > 0, distance > distanceEpsilon else { return nil }
        return distance / elapsed
    }

    private static func plausibleSpeed(_ speed: Double?) -> Double? {
        guard let speed,
              speed.isFinite,
              speed >= minimumMovingSpeedMetersPerSecond,
              speed <= maximumPlausibleStartupSpeedMetersPerSecond else {
            return nil
        }
        return speed
    }

    private static func trimmedIncompleteTail(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.count > 1 else { return samples }

        let expected = ExpectedTelemetryChannels(samples: samples)
        guard expected.hasRequiredChannel else { return samples }

        var lastCompleteIndex = samples.count - 1
        while lastCompleteIndex > 0,
              !expected.isComplete(samples[lastCompleteIndex]) {
            lastCompleteIndex -= 1
        }

        guard lastCompleteIndex < samples.count - 1 else { return samples }
        return Array(samples[...lastCompleteIndex])
    }

    private static func resampled(samples: [TelemetrySample], interval: TimeInterval) -> [TelemetrySample] {
        guard samples.count > 1, interval > 0 else { return samples }

        var output: [TelemetrySample] = []
        output.reserveCapacity(samples.count)

        for index in 0..<(samples.count - 1) {
            let current = samples[index]
            let next = samples[index + 1]
            if output.last?.elapsed != current.elapsed {
                output.append(current)
            }

            let gap = next.elapsed - current.elapsed
            guard gap > interval else { continue }

            var elapsed = current.elapsed + interval
            while elapsed < next.elapsed {
                let fraction = min(1, max(0, (elapsed - current.elapsed) / gap))
                output.append(interpolate(current, next, fraction: fraction, elapsed: elapsed))
                elapsed += interval
            }
        }

        if let last = samples.last, output.last?.elapsed != last.elapsed {
            output.append(last)
        }

        return output
    }

    private static func computeBounds(samples: [TelemetrySample]) -> GeoBounds? {
        var minLatitude = Double.greatestFiniteMagnitude
        var maxLatitude = -Double.greatestFiniteMagnitude
        var minLongitude = Double.greatestFiniteMagnitude
        var maxLongitude = -Double.greatestFiniteMagnitude
        var found = false

        for sample in samples {
            guard let latitude = sample.latitude, let longitude = sample.longitude else { continue }
            minLatitude = min(minLatitude, latitude)
            maxLatitude = max(maxLatitude, latitude)
            minLongitude = min(minLongitude, longitude)
            maxLongitude = max(maxLongitude, longitude)
            found = true
        }

        guard found else { return nil }
        return GeoBounds(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }

    private static func haversineMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let radius = 6_371_000.0
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let deltaPhi = (latitude2 - latitude1) * .pi / 180
        let deltaLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private struct ExpectedTelemetryChannels {
    let needsPosition: Bool
    let needsHeartRate: Bool
    let needsCadence: Bool
    let needsDistance: Bool
    let needsSpeed: Bool

    init(samples: [TelemetrySample]) {
        let threshold = max(1, Int((Double(samples.count) * 0.5).rounded(.up)))
        needsPosition = samples.filter { $0.latitude != nil && $0.longitude != nil }.count >= threshold
        needsHeartRate = samples.filter { $0.heartRate != nil }.count >= threshold
        needsCadence = samples.filter { $0.cadence != nil }.count >= threshold
        needsDistance = samples.filter { $0.distanceMeters?.isFinite == true }.count >= threshold
        needsSpeed = samples.filter { $0.speedMetersPerSecond?.isFinite == true }.count >= threshold
    }

    var hasRequiredChannel: Bool {
        needsPosition || needsHeartRate || needsCadence || needsDistance || needsSpeed
    }

    func isComplete(_ sample: TelemetrySample) -> Bool {
        if needsPosition, sample.latitude == nil || sample.longitude == nil { return false }
        if needsHeartRate, sample.heartRate == nil { return false }
        if needsCadence, sample.cadence == nil { return false }
        if needsDistance, sample.distanceMeters?.isFinite != true { return false }
        if needsSpeed, sample.speedMetersPerSecond?.isFinite != true { return false }
        return true
    }
}
