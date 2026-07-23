import Foundation

struct AltitudeProfileVertex: Equatable {
    var distanceMeters: Double
    var altitudeMeters: Double
}

struct AltitudeProfileGeometry: Equatable {
    static let maximumVertexCount = 4_096

    var vertices: [AltitudeProfileVertex]
    var minimumAltitudeMeters: Double
    var maximumAltitudeMeters: Double
    var totalDistanceMeters: Double

    static let empty = AltitudeProfileGeometry(
        vertices: [],
        minimumAltitudeMeters: 0,
        maximumAltitudeMeters: 0,
        totalDistanceMeters: 0
    )

    static func build(samples: [TelemetrySample], totalDistanceMeters: Double) -> AltitudeProfileGeometry {
        guard samples.count >= 2, totalDistanceMeters.isFinite, totalDistanceMeters >= 0 else {
            return .empty
        }

        var finite: [AltitudeProfileVertex] = []
        finite.reserveCapacity(samples.count)
        for sample in samples {
            guard let distance = sample.distanceMeters,
                  let altitude = sample.altitudeMeters,
                  distance.isFinite,
                  altitude.isFinite,
                  distance >= 0,
                  finite.last.map({ distance >= $0.distanceMeters }) ?? true else {
                continue
            }

            let vertex = AltitudeProfileVertex(distanceMeters: distance, altitudeMeters: altitude)
            if let last = finite.last, abs(distance - last.distanceMeters) <= 0.000_001 {
                finite[finite.count - 1] = vertex
            } else {
                finite.append(vertex)
            }
        }

        guard finite.count >= 2 else { return .empty }
        let resolvedTotalDistance = max(totalDistanceMeters, finite[finite.count - 1].distanceMeters)
        guard resolvedTotalDistance > 0 else { return .empty }
        if resolvedTotalDistance > finite[finite.count - 1].distanceMeters + 0.000_001 {
            finite.append(AltitudeProfileVertex(
                distanceMeters: resolvedTotalDistance,
                altitudeMeters: finite[finite.count - 1].altitudeMeters
            ))
        }

        let minimumAltitude = finite.map(\.altitudeMeters).min() ?? 0
        let maximumAltitude = finite.map(\.altitudeMeters).max() ?? 0
        let vertices: [AltitudeProfileVertex]
        if finite.count <= maximumVertexCount {
            vertices = finite
        } else {
            let stride = Double(finite.count - 1) / Double(maximumVertexCount - 1)
            vertices = (0..<maximumVertexCount).map { outputIndex in
                let sourceIndex = min(finite.count - 1, Int((Double(outputIndex) * stride).rounded()))
                return finite[sourceIndex]
            }
        }

        return AltitudeProfileGeometry(
            vertices: vertices,
            minimumAltitudeMeters: minimumAltitude,
            maximumAltitudeMeters: maximumAltitude,
            totalDistanceMeters: resolvedTotalDistance
        )
    }

    func altitude(atDistanceMeters distance: Double) -> Double? {
        guard vertices.count >= 2, distance.isFinite else { return nil }
        if distance <= vertices[0].distanceMeters {
            return vertices[0].altitudeMeters
        }
        if distance >= vertices[vertices.count - 1].distanceMeters {
            return vertices[vertices.count - 1].altitudeMeters
        }

        var low = 0
        var high = vertices.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if vertices[middle].distanceMeters <= distance {
                low = middle
            } else {
                high = middle
            }
        }
        let a = vertices[low]
        let b = vertices[high]
        let span = b.distanceMeters - a.distanceMeters
        let fraction = span > 0 ? min(1, max(0, (distance - a.distanceMeters) / span)) : 1
        let altitude = a.altitudeMeters + (b.altitudeMeters - a.altitudeMeters) * fraction
        return altitude.isFinite ? altitude : nil
    }
}
