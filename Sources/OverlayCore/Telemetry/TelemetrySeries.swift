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
    private static let maximumStartupPaceSmoothingElapsed: TimeInterval = 10
    private static let startupPaceSmoothingExponent = 1.7
    private static let startupSegmentConsistencyRatio = 1.6
    private static let startupSpeedJumpRatio = 1.6
    private static let distanceEpsilon = 0.001

    public init(samples: [TelemetrySample]) {
        let sorted = samples.sorted { lhs, rhs in
            if lhs.elapsed == rhs.elapsed {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.elapsed < rhs.elapsed
        }

        let normalized = TelemetrySeries.normalized(samples: sorted)
        let speedEnriched = TelemetrySeries.enrichedWithDistanceDerivedSpeed(samples: normalized)
        let startupSpeedStabilized = TelemetrySeries.stabilizedStartupSpeedJumps(samples: speedEnriched)
        let cadenceEnriched = TelemetrySeries.enrichedWithStartupCadence(samples: startupSpeedStabilized, interval: Self.resampleInterval)
        let resampled = TelemetrySeries.resampled(samples: cadenceEnriched, interval: Self.resampleInterval)
        let startupSmoothed = TelemetrySeries.smoothedStartupPace(samples: resampled)
        self.samples = TelemetrySeries.trimmedIncompleteTail(samples: startupSmoothed)
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

    private func interpolate(
        _ a: TelemetrySample,
        _ b: TelemetrySample,
        fraction: Double,
        elapsed: TimeInterval
    ) -> TelemetrySample {
        Self.interpolate(a, b, fraction: fraction, elapsed: elapsed)
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
        guard let lhs = a, let rhs = b else {
            return nearest(a, b, fraction: fraction)
        }
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
        var previousInput: TelemetrySample?
        var previousOutput: TelemetrySample?
        var accumulatedDistance = 0.0
        var output: [TelemetrySample] = []

        for input in samples {
            var sample = input

            if let distance = input.distanceMeters {
                accumulatedDistance = max(0, distance - firstDistance)
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

            if sample.speedMetersPerSecond == nil,
               let previousOutput,
               input.elapsed > previousOutput.elapsed {
                let deltaDistance = accumulatedDistance - (previousOutput.distanceMeters ?? accumulatedDistance)
                let deltaTime = input.elapsed - previousOutput.elapsed
                if deltaDistance >= 0, deltaTime > 0 {
                    sample.speedMetersPerSecond = deltaDistance / deltaTime
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

    private static func stabilizedStartupSpeedJumps(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.count > 2 else { return samples }

        var output = samples
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let current = samples[index]
            let next = samples[index + 1]
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
        interval: TimeInterval
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
                targetCadence: targetCadence
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
                    targetCadence: targetCadence
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
        targetCadence: Int
    ) -> Int {
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

    private static func smoothedStartupPace(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard samples.count > 1,
              let targetIndex = samples.firstIndex(where: { sample in
                  guard let distance = sample.distanceMeters, distance > distanceEpsilon else { return false }
                  let speed = sample.speedMetersPerSecond ?? (sample.elapsed > 0 ? distance / sample.elapsed : nil)
                  guard let speed, speed.isFinite else { return false }
                  return speed >= minimumMovingSpeedMetersPerSecond
                      && speed <= maximumPlausibleStartupSpeedMetersPerSecond
              }) else {
            return samples
        }

        let target = samples[targetIndex]
        guard targetIndex > 0,
              target.elapsed > 0,
              target.elapsed <= maximumStartupPaceSmoothingElapsed else {
            return samples
        }
        guard samples[..<targetIndex].allSatisfy({ ($0.distanceMeters ?? 0) <= distanceEpsilon }) else {
            return samples
        }

        let targetSpeed = target.speedMetersPerSecond ?? ((target.distanceMeters ?? 0) / target.elapsed)
        guard targetSpeed.isFinite,
              targetSpeed >= minimumMovingSpeedMetersPerSecond,
              targetSpeed <= maximumPlausibleStartupSpeedMetersPerSecond else {
            return samples
        }
        guard samples[..<targetIndex].contains(where: { sample in
            shouldReplaceStartupSpeed(sample.speedMetersPerSecond, targetSpeed: targetSpeed)
                && (sample.distanceMeters ?? 0) <= distanceEpsilon
                && (sample.speedMetersPerSecond ?? 0) > targetSpeed
        }) else {
            return samples
        }

        let startSpeed = min(
            targetSpeed,
            max(startupRampMinimumSpeedMetersPerSecond, targetSpeed * startupRampSpeedRatio)
        )

        var output = samples
        for index in 0..<targetIndex {
            let sample = samples[index]
            let progress = min(1, max(0, sample.elapsed / target.elapsed))
            let easedProgress = pow(progress, startupPaceSmoothingExponent)
            let rampSpeed = startSpeed + ((targetSpeed - startSpeed) * easedProgress)
            if shouldReplaceStartupSpeed(sample.speedMetersPerSecond, targetSpeed: targetSpeed)
                || (sample.distanceMeters ?? 0) <= distanceEpsilon {
                output[index].speedMetersPerSecond = rampSpeed
            }
        }
        return output
    }

    private static func shouldReplaceStartupSpeed(_ speed: Double?, targetSpeed: Double) -> Bool {
        guard let speed, speed.isFinite else { return true }
        guard speed >= minimumMovingSpeedMetersPerSecond else { return true }
        return speed > targetSpeed * 1.75
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
