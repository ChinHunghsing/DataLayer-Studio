import Foundation

public struct GeoBounds: Equatable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double
}

public struct TelemetrySeries {
    public private(set) var samples: [TelemetrySample]
    public let bounds: GeoBounds?
    private static let resampleInterval: TimeInterval = 1
    private static let minimumMovingSpeedMetersPerSecond = 0.3

    public init(samples: [TelemetrySample]) {
        let sorted = samples.sorted { lhs, rhs in
            if lhs.elapsed == rhs.elapsed {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.elapsed < rhs.elapsed
        }

        let normalized = TelemetrySeries.normalized(samples: sorted)
        let speedEnriched = TelemetrySeries.enrichedWithDistanceDerivedSpeed(samples: normalized)
        self.samples = TelemetrySeries.resampled(samples: speedEnriched, interval: Self.resampleInterval)
        self.bounds = TelemetrySeries.computeBounds(samples: self.samples)
    }

    public var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.elapsed - first.elapsed)
    }

    public var isEmpty: Bool {
        samples.isEmpty
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
            cadence: nearest(a.cadence, b.cadence, fraction: fraction),
            distanceMeters: interpolate(a.distanceMeters, b.distanceMeters, fraction: fraction),
            speedMetersPerSecond: interpolate(a.speedMetersPerSecond, b.speedMetersPerSecond, fraction: fraction),
            powerWatts: nearest(a.powerWatts, b.powerWatts, fraction: fraction),
            temperatureCelsius: nearest(a.temperatureCelsius, b.temperatureCelsius, fraction: fraction)
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

    private static func interpolatedDate(_ a: Date?, _ b: Date?, fraction: Double) -> Date? {
        guard let a, let b else { return a ?? b }
        return a.addingTimeInterval(b.timeIntervalSince(a) * fraction)
    }

    private static func normalized(samples: [TelemetrySample]) -> [TelemetrySample] {
        guard !samples.isEmpty else { return [] }

        let firstDistance = samples.compactMap(\.distanceMeters).first ?? 0
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
                output[index].speedMetersPerSecond = segmentSpeed
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
