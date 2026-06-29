import Foundation
@testable import OverlayCore
import XCTest

final class GPXParserTests: XCTestCase {
    func testParsesTrackPointsAndExtensions() throws {
        let series = try GPXParser().parse(data: Data(sampleGPX.utf8))

        XCTAssertEqual(series.samples.count, 3)

        let start = series.sample(at: 0)
        let end = series.sample(at: 2)

        XCTAssertEqual(start.elapsed, 0)
        XCTAssertEqual(start.latitude ?? 0, 34.6829573, accuracy: 0.0000001)
        XCTAssertEqual(start.longitude ?? 0, 135.5322092, accuracy: 0.0000001)
        XCTAssertEqual(start.altitudeMeters ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(start.distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(start.speedMetersPerSecond ?? -1, 3.0, accuracy: 0.001)
        XCTAssertEqual(start.heartRate, 110)
        XCTAssertEqual(start.cadence, 198)
        XCTAssertEqual(start.powerWatts, 250)
        XCTAssertEqual(start.temperatureCelsius, 23)

        XCTAssertEqual(end.elapsed, 2)
        XCTAssertEqual(end.distanceMeters ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(end.speedMetersPerSecond ?? -1, 4.0, accuracy: 0.001)
        XCTAssertEqual(end.heartRate, 112)
        XCTAssertEqual(end.cadence, 200)
    }

    func testTelemetryFileParserRoutesGPXFiles() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gpx")
        try Data(sampleGPX.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let series = try TelemetryFileParser().parse(url: url)

        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 8, accuracy: 0.001)
    }

    func testRejectsUnsupportedActivityExtensions() {
        let url = URL(fileURLWithPath: "/tmp/activity.tcx")

        XCTAssertThrowsError(try TelemetryFileParser().parse(url: url)) { error in
            guard case TelemetryFileError.unsupportedExtension("tcx") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private let sampleGPX = """
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="COROS Wearables"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxdata="http://www.cluetrust.com/XML/GPXDATA/1/0"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <trkseg>
      <trkpt lat="34.6829573" lon="135.5322092">
        <ele>15</ele>
        <time>2026-06-27T21:32:53Z</time>
        <extensions>
          <gpxdata:hr>110</gpxdata:hr>
          <gpxdata:distance>100.00</gpxdata:distance>
          <gpxdata:cadence>99</gpxdata:cadence>
          <gpxdata:speed>3.000</gpxdata:speed>
          <gpxdata:power>250</gpxdata:power>
          <gpxdata:temperature>23</gpxdata:temperature>
        </extensions>
      </trkpt>
      <trkpt lat="34.6829682" lon="135.5322337">
        <ele>16</ele>
        <time>2026-06-27T21:32:54Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>111</gpxtpx:hr>
            <gpxtpx:cad>99</gpxtpx:cad>
            <gpxtpx:atemp>24</gpxtpx:atemp>
          </gpxtpx:TrackPointExtension>
          <gpxdata:distance>104.00</gpxdata:distance>
          <gpxdata:speed>3.500</gpxdata:speed>
        </extensions>
      </trkpt>
      <trkpt lat="34.6829796" lon="135.5322510">
        <ele>16</ele>
        <time>2026-06-27T21:32:55Z</time>
        <extensions>
          <gpxdata:hr>112</gpxdata:hr>
          <gpxdata:distance>108.00</gpxdata:distance>
          <gpxdata:cadence>100</gpxdata:cadence>
          <gpxdata:speed>4.000</gpxdata:speed>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
"""
