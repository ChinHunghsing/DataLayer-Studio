import Foundation

public struct GeoBounds: Equatable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double
}

/// A wall-clock span during which the activity timer was paused, relative to the activity's
/// wall-clock start. The series' public time axis includes these spans so a continuously
/// recorded video stays in sync across pauses; sample lookups inside a paused span hold the
/// values from the moment the timer stopped.
public struct TelemetryPausedRange: Equatable {
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }

    public var end: TimeInterval { start + duration }
}

public struct TelemetrySeries: Equatable {
    public private(set) var samples: [TelemetrySample]
    public let bounds: GeoBounds?
    /// Wall-clock pause spans, sorted and disjoint. `samples` stay on the timer axis (pauses
    /// excluded); every public time-based API works on the wall axis and converts internally.
    public let pausedRanges: [TelemetryPausedRange]
    private static let resampleInterval: TimeInterval = 1
    /// Preserve every source sample, but never amplify sparse/untrusted input beyond this total.
    private static let maximumResampledSampleCount = 100_000
    /// 距离导出补速的段时长下限：只排除锚点/末帧插入产生的亚秒合成段，
    /// 设备真实记录间隔不短于 0.25s 的场合不受影响
    private static let minimumSpeedDerivationSegmentSeconds: TimeInterval = 0.5
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
    private static let resumptionQuietSpeedMetersPerSecond = 2.0
    private static let resumptionMinimumQuietDuration: TimeInterval = 5
    private static let resumptionRunningSpeedFloorMetersPerSecond = 2.5
    private static let resumptionPlateauPersistenceDuration: TimeInterval = 5
    private static let resumptionRunningCadenceStepsPerMinute = 140
    private static let resumptionQuietSegmentSpeedMetersPerSecond = 2.5
    private static let distanceEpsilon = 0.001
    private static let minimumAscentDeltaMeters = 1.0

    public init(samples: [TelemetrySample], pausedRanges: [TelemetryPausedRange] = []) {
        self.pausedRanges = TelemetrySeries.sanitizedPausedRanges(pausedRanges)
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
        let resumptionSmoothed = TelemetrySeries.appliedMotionResumptions(
            samples: startupSmoothed,
            corrections: TelemetrySeries.motionResumptionCorrections(in: normalized)
        )
        let edgeSmoothed = TelemetrySeries.smoothedEdgeSpeedPlateaus(
            samples: resumptionSmoothed,
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

    /// Wall-clock duration: timer duration plus every paused span inside the recording.
    public var duration: TimeInterval {
        wallElapsed(forActiveElapsed: activeDuration)
    }

    /// Timer-axis duration (pauses excluded); the span actually covered by `samples`.
    public var activeDuration: TimeInterval {
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
        return date.addingTimeInterval(-wallElapsed(forActiveElapsed: datedSample.elapsed))
    }

    /// Timer-axis time for a wall-clock time. Inside a paused span this stays at the pause
    /// start, which is what makes paused lookups hold the last pre-pause values.
    public func activeElapsed(forWallElapsed wall: TimeInterval) -> TimeInterval {
        guard wall.isFinite, !pausedRanges.isEmpty else { return wall }
        var active = wall
        for range in pausedRanges {
            if wall >= range.end {
                active -= range.duration
            } else if wall > range.start {
                active -= wall - range.start
            }
        }
        return active
    }

    /// Wall-clock time at which a timer-axis time occurs (the resume edge for paused spans).
    public func wallElapsed(forActiveElapsed active: TimeInterval) -> TimeInterval {
        guard active.isFinite, !pausedRanges.isEmpty else { return active }
        var shift: TimeInterval = 0
        for range in pausedRanges {
            let activeAtRangeStart = range.start - shift
            guard active > activeAtRangeStart else { break }
            shift += range.duration
        }
        return active + shift
    }

    public func date(atElapsed elapsed: TimeInterval) -> Date? {
        guard elapsed.isFinite else { return nil }
        if !pausedRanges.isEmpty, let activityStartDate {
            // The wall clock keeps running while the timer is paused.
            return activityStartDate.addingTimeInterval(elapsed)
        }
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

    /// Sample at a wall-clock time. Paused spans hold the pause-start sample.
    public func sample(at elapsed: TimeInterval) -> TelemetrySample {
        sampleAtActiveElapsed(activeElapsed(forWallElapsed: elapsed))
    }

    private func sampleAtActiveElapsed(_ elapsed: TimeInterval) -> TelemetrySample {
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
        if Self.isTrackSegmentBreak(from: a, to: b) {
            return Self.heldSample(a, at: elapsed)
        }
        let span = max(b.elapsed - a.elapsed, 0.000_001)
        let fraction = min(1, max(0, (elapsed - a.elapsed) / span))
        return interpolate(a, b, fraction: fraction, elapsed: elapsed)
    }

    public func trimmed(by trim: ActivityTrim) -> TelemetrySeries {
        guard !samples.isEmpty else { return self }
        let sourceDuration = duration
        guard trim.isActive(for: sourceDuration) else { return self }

        // Trim bounds arrive on the wall axis; samples are cut on the timer axis.
        let trimStart = trim.start(in: sourceDuration)
        let trimEnd = trim.end(in: sourceDuration)
        let activeStart = activeElapsed(forWallElapsed: trimStart)
        let activeEnd = activeElapsed(forWallElapsed: trimEnd)
        let startSample = sampleAtActiveElapsed(activeStart)
        let endSample = sampleAtActiveElapsed(activeEnd)
        let distanceOffset = startSample.distanceMeters
        let calorieOffset = startSample.totalCalories
        let ascentOffset = startSample.totalAscentMeters

        var trimmedSamples: [TelemetrySample] = [
            rebasedSample(
                startSample,
                trimStart: activeStart,
                distanceOffset: distanceOffset,
                calorieOffset: calorieOffset,
                ascentOffset: ascentOffset
            )
        ]

        for sample in samples where sample.elapsed > activeStart && sample.elapsed < activeEnd {
            trimmedSamples.append(
                rebasedSample(
                    sample,
                    trimStart: activeStart,
                    distanceOffset: distanceOffset,
                    calorieOffset: calorieOffset,
                    ascentOffset: ascentOffset
                )
            )
        }

        if activeEnd > activeStart {
            let rebasedEnd = rebasedSample(
                endSample,
                trimStart: activeStart,
                distanceOffset: distanceOffset,
                calorieOffset: calorieOffset,
                ascentOffset: ascentOffset
            )
            if trimmedSamples.last?.elapsed != rebasedEnd.elapsed {
                trimmedSamples.append(rebasedEnd)
            }
        }

        // Pause spans that survive the trim shift onto the new wall axis.
        let trimmedRanges = pausedRanges.compactMap { range -> TelemetryPausedRange? in
            let start = max(range.start, trimStart)
            let end = min(range.end, trimEnd)
            guard end - start > 1e-9 else { return nil }
            return TelemetryPausedRange(start: start - trimStart, duration: end - start)
        }

        return TelemetrySeries(samples: trimmedSamples, pausedRanges: trimmedRanges)
    }

    private func interpolate(
        _ a: TelemetrySample,
        _ b: TelemetrySample,
        fraction: Double,
        elapsed: TimeInterval
    ) -> TelemetrySample {
        Self.interpolate(a, b, fraction: fraction, elapsed: elapsed)
    }

    private static func sanitizedPausedRanges(_ ranges: [TelemetryPausedRange]) -> [TelemetryPausedRange] {
        let positive = ranges
            .filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 && $0.start >= 0 }
            .sorted { $0.start < $1.start }
        var merged: [TelemetryPausedRange] = []
        for range in positive {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = TelemetryPausedRange(
                    start: last.start,
                    duration: max(last.end, range.end) - last.start
                )
            } else {
                merged.append(range)
            }
        }
        return merged
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
            weatherSummary: nearest(a.weatherSummary, b.weatherSummary, fraction: fraction),
            trackSegmentIndex: fraction < 1 ? a.trackSegmentIndex : b.trackSegmentIndex
        )
    }

    private static func isTrackSegmentBreak(from a: TelemetrySample, to b: TelemetrySample) -> Bool {
        a.trackSegmentIndex != b.trackSegmentIndex
    }

    private static func heldSample(_ sample: TelemetrySample, at elapsed: TimeInterval) -> TelemetrySample {
        var held = sample
        held.elapsed = elapsed
        if let date = sample.date {
            held.date = date.addingTimeInterval(elapsed - sample.elapsed)
        }
        return held
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
                !isTrackSegmentBreak(from: previousInput, to: input),
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
        guard !(1...targetIndex).contains(where: {
            isTrackSegmentBreak(from: samples[$0 - 1], to: samples[$0])
        }) else {
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
            guard !isTrackSegmentBreak(from: current, to: next) else { continue }
            guard let currentDistance = current.distanceMeters,
                  let nextDistance = next.distanceMeters else {
                continue
            }

            let deltaTime = next.elapsed - current.elapsed
            let deltaDistance = nextDistance - currentDistance
            guard deltaTime > 0, deltaDistance > 0 else { continue }
            // 亚秒合成段（锚点/末帧插入的产物）会把毫米级距离差放大成冲刺
            // 段速，不作补速依据；整秒真实段（含骑行/滑雪 >12 m/s 的合法
            // 高速）不受影响
            guard deltaTime >= minimumSpeedDerivationSegmentSeconds else { continue }

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
        var previous: TelemetrySample?
        var totalAscent = 0.0
        return samples.map { input in
            var sample = input
            if let previous, isTrackSegmentBreak(from: previous, to: input) {
                referenceAltitude = nil
            }
            previous = input
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
            guard !isTrackSegmentBreak(from: previous, to: current),
                  !isTrackSegmentBreak(from: current, to: next) else {
                continue
            }
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
        guard !(1...targetIndex).contains(where: {
            isTrackSegmentBreak(from: samples[$0 - 1], to: samples[$0])
        }) else {
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

        let gap = target.elapsed - first.elapsed
        let requiredInsertions = ceil(gap / interval) - 1
        let availableInsertions = max(0, maximumResampledSampleCount - output.count)
        guard requiredInsertions.isFinite,
              requiredInsertions <= Double(availableInsertions) else {
            return output
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
        if isTrackSegmentBreak(from: a, to: b) {
            return heldSample(a, at: elapsed)
        }
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

    struct MotionResumptionCorrection {
        var anchorElapsed: TimeInterval
        var stabilizationElapsed: TimeInterval
        var baseSpeed: Double
        var targetSpeed: Double
        var rampDuration: TimeInterval
    }

    /// 检测组间休息后的奔跑恢复点：静息（走路/站立）之后设备距离猛补、速度滞后爬升的形态，
    /// 与活动起跑的补账签名同源。在既有四条件之上增加两道闸：
    /// 稳定平台必须是持续的奔跑速度（排除“走两步就停下喝水”的微移动），
    /// 距离超前证据必须有跑步步频或后续持续位移佐证（排除站立时的 GPS 漂移脉冲）。
    static func motionResumptionCorrections(in samples: [TelemetrySample]) -> [MotionResumptionCorrection] {
        guard samples.count > 4, let first = samples.first, let last = samples.last else { return [] }
        let firstElapsed = first.elapsed

        func deviceSpeed(_ index: Int) -> Double {
            guard let value = samples[index].speedMetersPerSecond, value.isFinite else { return 0 }
            return max(0, value)
        }
        func segmentSpeed(into index: Int) -> Double? {
            guard index > 0,
                  let distance = samples[index].distanceMeters,
                  let previous = samples[index - 1].distanceMeters else { return nil }
            let deltaTime = samples[index].elapsed - samples[index - 1].elapsed
            guard deltaTime > 0 else { return nil }
            return (distance - previous) / deltaTime
        }

        var corrections: [MotionResumptionCorrection] = []
        // 活动起跑窗口由起跑补账路径处理，恢复点扫描从窗口之后开始
        var index = samples.firstIndex {
            $0.elapsed - firstElapsed > maximumStartupPaceSmoothingElapsed
        } ?? samples.count

        while index < samples.count {
            // 静息区：连续低于静息速度阈值且时长达标
            while index < samples.count, deviceSpeed(index) >= resumptionQuietSpeedMetersPerSecond {
                index += 1
            }
            guard index < samples.count else { break }
            let quietStart = index
            while index < samples.count, deviceSpeed(index) < resumptionQuietSpeedMetersPerSecond {
                index += 1
            }
            guard index < samples.count else { break }
            let quietEnd = index - 1
            guard samples[quietEnd].elapsed - samples[quietStart].elapsed >= resumptionMinimumQuietDuration else {
                continue
            }

            // 稳定点：静息结束后一个窗口内速度进入奔跑平台
            var stabilization: Int?
            var probe = index
            while probe + 2 < samples.count,
                  samples[probe].elapsed - samples[quietEnd].elapsed <= maximumStartupPaceSmoothingElapsed {
                let v0 = deviceSpeed(probe)
                let v1 = deviceSpeed(probe + 1)
                let v2 = deviceSpeed(probe + 2)
                if v0 >= resumptionRunningSpeedFloorMetersPerSecond,
                   abs(v1 - v0) <= startupStaleSpeedToleranceMetersPerSecond,
                   abs(v2 - v1) <= startupStaleSpeedToleranceMetersPerSecond {
                    stabilization = probe
                    break
                }
                probe += 1
            }
            guard let stabilization,
                  let targetSpeed = plausibleSpeed(samples[stabilization].speedMetersPerSecond) else {
                continue
            }

            // 平台必须持续：稳定点之后一段时间内速度不塌回
            let persistenceEnd = samples[stabilization].elapsed + resumptionPlateauPersistenceDuration
            guard last.elapsed >= persistenceEnd else { continue }
            var persistent = true
            var check = stabilization
            while check < samples.count, samples[check].elapsed <= persistenceEnd {
                if deviceSpeed(check) < targetSpeed * 0.8 {
                    persistent = false
                    break
                }
                check += 1
            }
            guard persistent else { continue }

            // 锚点：从静息区末端向前回退，跳过发射时的距离补账段，
            // 锚点之前的走动/喝水/站立保持原始数据
            var anchor = quietEnd
            while anchor > quietStart,
                  let segment = segmentSpeed(into: anchor),
                  segment >= resumptionQuietSegmentSpeedMetersPerSecond {
                anchor -= 1
            }
            let anchorElapsed = samples[anchor].elapsed
            let stabilizationElapsed = samples[stabilization].elapsed
            let windowDuration = stabilizationElapsed - anchorElapsed
            guard windowDuration > 1,
                  windowDuration <= maximumStartupPaceSmoothingElapsed * 2 else {
                continue
            }

            let baseSpeed = max(deviceSpeed(anchor), startupRampMinimumSpeedMetersPerSecond)
            guard targetSpeed / max(baseSpeed, minimumMovingSpeedMetersPerSecond) >= startupSpeedJumpRatio else {
                continue
            }

            // 单调爬升（低于移动阈值的样本不参与判定）
            var previousSpeed = 0.0
            var monotone = true
            for candidate in (anchor + 1)...stabilization {
                let speed = deviceSpeed(candidate)
                guard speed >= minimumMovingSpeedMetersPerSecond else { continue }
                if speed < previousSpeed - startupStaleSpeedToleranceMetersPerSecond {
                    monotone = false
                    break
                }
                previousSpeed = speed
            }
            guard monotone else { continue }

            // 距离超前证据 + 佐证（跑步步频，或其后 3 秒距离保持奔跑量级）
            var evidence = false
            for candidate in (anchor + 1)...stabilization {
                guard let segment = segmentSpeed(into: candidate) else { continue }
                let device = max(deviceSpeed(candidate), minimumMovingSpeedMetersPerSecond)
                guard segment >= startupSpeedJumpRatio * device else { continue }
                if (samples[candidate].cadence ?? 0) >= resumptionRunningCadenceStepsPerMinute {
                    evidence = true
                    break
                }
                let horizon = samples[candidate].elapsed + 3
                var follower = candidate
                while follower + 1 < samples.count, samples[follower + 1].elapsed <= horizon {
                    follower += 1
                }
                if follower > candidate,
                   let followDistance = samples[follower].distanceMeters,
                   let candidateDistance = samples[candidate].distanceMeters,
                   samples[follower].elapsed > samples[candidate].elapsed,
                   (followDistance - candidateDistance) / (samples[follower].elapsed - samples[candidate].elapsed)
                       >= resumptionRunningSpeedFloorMetersPerSecond {
                    evidence = true
                    break
                }
            }
            guard evidence else { continue }

            // 累计距离明显超过设备速度积分
            guard let anchorDistance = samples[anchor].distanceMeters,
                  let stabilizationDistance = samples[stabilization].distanceMeters else {
                continue
            }
            let coveredDistance = stabilizationDistance - anchorDistance
            guard coveredDistance > distanceEpsilon else { continue }
            var speedIntegral = 0.0
            for candidate in (anchor + 1)...stabilization {
                let deltaTime = samples[candidate].elapsed - samples[candidate - 1].elapsed
                guard deltaTime > 0 else { continue }
                speedIntegral += (deviceSpeed(candidate - 1) + deviceSpeed(candidate)) / 2 * deltaTime
            }
            guard coveredDistance > startupCatchUpIntegralRatio * speedIntegral else { continue }

            let exponent = 1 / startupPaceSmoothingExponent
            let coefficient = (targetSpeed - baseSpeed) * (1 - 1 / (exponent + 1))
            guard coefficient > 0 else { continue }
            let rawDuration = (targetSpeed * windowDuration - coveredDistance) / coefficient
            let rampDuration = min(max(rawDuration, minimumStartupCatchUpRampDuration), windowDuration)

            corrections.append(MotionResumptionCorrection(
                anchorElapsed: anchorElapsed,
                stabilizationElapsed: stabilizationElapsed,
                baseSpeed: baseSpeed,
                targetSpeed: targetSpeed,
                rampDuration: rampDuration
            ))
            index = max(check, stabilization + 1)
        }
        return corrections
    }

    private static func appliedMotionResumptions(
        samples: [TelemetrySample],
        corrections: [MotionResumptionCorrection]
    ) -> [TelemetrySample] {
        guard !corrections.isEmpty else { return samples }

        var output = samples
        let exponent = 1 / startupPaceSmoothingExponent
        for correction in corrections {
            guard let anchorIndex = output.lastIndex(where: { $0.elapsed <= correction.anchorElapsed + 0.000_5 }),
                  let stabilizationIndex = output.firstIndex(where: { $0.elapsed >= correction.stabilizationElapsed - 0.000_5 }),
                  anchorIndex < stabilizationIndex else {
                continue
            }

            // 发射首秒设备速度可能还是 0，其距离补账段速会被距离补速回写到
            // 锚点样本上；斜坡从锚点起坡，锚点自身必须回到起点速度，否则
            // 起跑前一秒会闪出补账段速
            output[anchorIndex].speedMetersPerSecond = correction.baseSpeed

            func rampSpeed(at elapsed: TimeInterval) -> Double {
                let time = elapsed - correction.anchorElapsed
                guard time > 0 else { return correction.baseSpeed }
                guard time < correction.rampDuration else { return correction.targetSpeed }
                let progress = pow(time / correction.rampDuration, exponent)
                return correction.baseSpeed + (correction.targetSpeed - correction.baseSpeed) * progress
            }

            for index in (anchorIndex + 1)..<stabilizationIndex {
                output[index].speedMetersPerSecond = rampSpeed(at: output[index].elapsed)
            }

            // 距离按修正后的速度积分重排并缩放，锚点与稳定点的实测距离保持不变
            guard let anchorDistance = output[anchorIndex].distanceMeters,
                  let stabilizationDistance = output[stabilizationIndex].distanceMeters else {
                continue
            }
            let coveredDistance = stabilizationDistance - anchorDistance
            guard coveredDistance > distanceEpsilon else { continue }

            let span = stabilizationIndex - anchorIndex
            var integrals = [Double](repeating: 0, count: span + 1)
            for offset in 1...span {
                let index = anchorIndex + offset
                let deltaTime = output[index].elapsed - output[index - 1].elapsed
                guard deltaTime > 0 else {
                    integrals[offset] = integrals[offset - 1]
                    continue
                }
                let previous = output[index - 1].speedMetersPerSecond ?? correction.baseSpeed
                let current = output[index].speedMetersPerSecond ?? correction.targetSpeed
                integrals[offset] = integrals[offset - 1] + (previous + current) / 2 * deltaTime
            }
            let total = integrals[span]
            guard total > distanceEpsilon else { continue }
            let scale = coveredDistance / total
            for offset in 1..<span {
                output[anchorIndex + offset].distanceMeters = anchorDistance + integrals[offset] * scale
            }
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
        // 证据门控：平台区间内必须有距离段速度与平台速度明显矛盾（速度停滞而距离在走，
        // 或距离停滞而速度停在高位），否则视为真实缓变数据，不重绘
        guard hasTrailingDistanceEvidence(samples: samples, from: start - 1, plateauSpeed: lastSpeed) else {
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

    /// 尾段重绘的距离证据：区间内存在与平台速度比值达到跳变阈值的距离段速度。
    /// 只统计不短于一个重采样间隔的段，锚点/最终样本插入产生的亚秒合成段不作证据。
    private static func hasTrailingDistanceEvidence(
        samples: [TelemetrySample],
        from start: Int,
        plateauSpeed: Double
    ) -> Bool {
        guard plateauSpeed > 0, start >= 0 else { return false }
        for index in (start + 1)..<samples.count {
            guard let previousDistance = samples[index - 1].distanceMeters,
                  let distance = samples[index].distanceMeters else {
                continue
            }
            let deltaTime = samples[index].elapsed - samples[index - 1].elapsed
            guard deltaTime >= resampleInterval - 0.001 else { continue }
            let segmentSpeed = (distance - previousDistance) / deltaTime
            let ratio = max(segmentSpeed, plateauSpeed) / max(min(segmentSpeed, plateauSpeed), 0.000_001)
            if ratio >= startupSpeedJumpRatio {
                return true
            }
        }
        return false
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
              !expected.isComplete(samples[lastCompleteIndex]),
              !hasTrailingMotionEvidence(samples: samples, at: lastCompleteIndex) {
            lastCompleteIndex -= 1
        }

        var output = lastCompleteIndex < samples.count - 1
            ? Array(samples[...lastCompleteIndex])
            : samples

        // 保留下来的运动尾段若缺心率/步频，延用最后已知值，保持叠加显示连续
        var lastFullyCompleteIndex = output.count - 1
        while lastFullyCompleteIndex > 0,
              !expected.isComplete(output[lastFullyCompleteIndex]) {
            lastFullyCompleteIndex -= 1
        }
        if lastFullyCompleteIndex < output.count - 1 {
            for index in (lastFullyCompleteIndex + 1)..<output.count {
                if output[index].heartRate == nil {
                    output[index].heartRate = output[index - 1].heartRate
                }
                if output[index].cadence == nil {
                    output[index].cadence = output[index - 1].cadence
                }
            }
        }
        return output
    }

    /// 尾段样本只要仍有位移或移动速度证据就保留；只裁掉纯心率/元数据尾巴。
    /// 归一化会给所有样本补距离和速度，所以证据必须看“距离是否仍在增长”而不是字段是否存在。
    private static func hasTrailingMotionEvidence(samples: [TelemetrySample], at index: Int) -> Bool {
        let sample = samples[index]
        if let speed = sample.speedMetersPerSecond,
           speed.isFinite,
           speed >= minimumMovingSpeedMetersPerSecond {
            return true
        }
        guard index > 0,
              let distance = sample.distanceMeters,
              let previousDistance = samples[index - 1].distanceMeters else {
            return false
        }
        return distance - previousDistance > distanceEpsilon
    }

    private static func resampled(samples: [TelemetrySample], interval: TimeInterval) -> [TelemetrySample] {
        guard samples.count > 1, interval > 0 else { return samples }

        var output: [TelemetrySample] = []
        output.reserveCapacity(samples.count)
        var availableInsertions = max(0, maximumResampledSampleCount - samples.count)

        for index in 0..<(samples.count - 1) {
            let current = samples[index]
            let next = samples[index + 1]
            if output.last?.elapsed != current.elapsed {
                output.append(current)
            }

            let gap = next.elapsed - current.elapsed
            guard gap.isFinite,
                  gap > interval,
                  !isTrackSegmentBreak(from: current, to: next) else {
                continue
            }

            let requiredInsertions = ceil(gap / interval) - 1
            guard requiredInsertions.isFinite,
                  requiredInsertions <= Double(availableInsertions) else {
                continue
            }
            availableInsertions -= Int(requiredInsertions)

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
