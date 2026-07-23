@testable import OverlayCore
import XCTest

final class AltitudeProfileGeometryTests: XCTestCase {
    func testGeometryUsesDistanceCollapsesPauseHoldAndExtendsToSessionEnd() {
        let geometry = AltitudeProfileGeometry.build(
            samples: [
                TelemetrySample(elapsed: 0, altitudeMeters: 100, distanceMeters: 0),
                TelemetrySample(elapsed: 1, altitudeMeters: 101, distanceMeters: 100),
                TelemetrySample(elapsed: 2, altitudeMeters: 102, distanceMeters: 100),
                TelemetrySample(elapsed: 3, altitudeMeters: 999, distanceMeters: 90),
                TelemetrySample(elapsed: 4, altitudeMeters: 103, distanceMeters: 200)
            ],
            totalDistanceMeters: 300
        )

        XCTAssertEqual(geometry.vertices, [
            AltitudeProfileVertex(distanceMeters: 0, altitudeMeters: 100),
            AltitudeProfileVertex(distanceMeters: 100, altitudeMeters: 102),
            AltitudeProfileVertex(distanceMeters: 200, altitudeMeters: 103),
            AltitudeProfileVertex(distanceMeters: 300, altitudeMeters: 103)
        ])
        XCTAssertEqual(geometry.minimumAltitudeMeters, 100)
        XCTAssertEqual(geometry.maximumAltitudeMeters, 103)
        XCTAssertEqual(geometry.totalDistanceMeters, 300)
        XCTAssertEqual(geometry.altitude(atDistanceMeters: 150) ?? -1, 102.5, accuracy: 0.000_001)
    }

    func testGeometryDownsamplesDeterministicallyAndKeepsEndpoints() {
        let samples = (0..<6_000).map { index in
            TelemetrySample(
                elapsed: TimeInterval(index),
                altitudeMeters: 100 + Double(index % 20),
                distanceMeters: Double(index)
            )
        }

        let geometry = AltitudeProfileGeometry.build(samples: samples, totalDistanceMeters: 5_999)

        XCTAssertEqual(geometry.vertices.count, 4_096)
        XCTAssertEqual(geometry.vertices.first?.distanceMeters, 0)
        XCTAssertEqual(geometry.vertices.last?.distanceMeters, 5_999)
    }

    func testGeometryIsEmptyWithoutTwoValidDistanceAltitudePoints() {
        let geometry = AltitudeProfileGeometry.build(
            samples: [
                TelemetrySample(elapsed: 0, altitudeMeters: 100),
                TelemetrySample(elapsed: 1, distanceMeters: 100)
            ],
            totalDistanceMeters: 100
        )

        XCTAssertEqual(geometry, .empty)
    }
}
