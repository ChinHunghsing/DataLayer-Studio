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

    func testParsesTrackTypeAsSport() throws {
        let parsed = try GPXParser().parseActivity(data: Data(sampleGPX.utf8))

        XCTAssertEqual(parsed.sport, .running)
    }

    func testSportTextMapping() {
        XCTAssertEqual(TelemetrySport(gpxTypeText: "trail_running"), .running)
        XCTAssertEqual(TelemetrySport(gpxTypeText: "Biking"), .cycling)
        XCTAssertEqual(TelemetrySport(gpxTypeText: "hiking"), .hiking)
        XCTAssertEqual(TelemetrySport(gpxTypeText: "9"), .generic)
        XCTAssertNil(TelemetrySport(gpxTypeText: ""))
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

    func testRejectsOversizedInputBeforeParsing() {
        let data = Data(count: GPXParser.maximumFileSizeBytes + 1)

        XCTAssertThrowsError(try GPXParser().parse(data: data)) { error in
            guard case GPXError.fileTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testIgnoresOutOfRangeIntegerExtensionsWithoutTrapping() throws {
        let gpx = """
        <gpx><trk><trkseg><trkpt lat="35" lon="139">
          <extensions><hr>1e300</hr><cadence>-1e300</cadence></extensions>
        </trkpt></trkseg></trk></gpx>
        """

        let sample = try GPXParser().parse(data: Data(gpx.utf8)).samples[0]

        XCTAssertNil(sample.heartRate)
        XCTAssertNil(sample.cadence)
    }

    func testMissingTimestampsProduceStrictlyIncreasingElapsedValues() throws {
        let gpx = """
        <gpx><trk><trkseg>
          <trkpt lat="35.0000" lon="139.0000" />
          <trkpt lat="35.0001" lon="139.0001"><time>2026-06-27T21:32:53Z</time></trkpt>
          <trkpt lat="35.0002" lon="139.0002" />
        </trkseg></trk></gpx>
        """

        let samples = try GPXParser().parse(data: Data(gpx.utf8)).samples

        XCTAssertEqual(samples.map(\.elapsed), [0, 1, 2])
    }

    /// 同秒采样在不少 GPX 导出里很常见（秒以下精度被截断、多段合并）。
    /// 逐点 +1 会凭空拉长轨迹总时长、令遥测与视频失步；相等则会被下游
    /// 去重整段丢弃。正确行为是亚秒步进：总时长几乎不变且样本全部保留。
    func testDuplicateTimestampsAreSeparatedWithoutInflatingDuration() throws {
        let gpx = """
        <gpx><trk><trkseg>
          <trkpt lat="35.0000" lon="139.0000"><time>2026-06-27T21:32:53Z</time></trkpt>
          <trkpt lat="35.0001" lon="139.0001"><time>2026-06-27T21:32:53Z</time></trkpt>
          <trkpt lat="35.0002" lon="139.0002"><time>2026-06-27T21:32:53Z</time></trkpt>
          <trkpt lat="35.0003" lon="139.0003"><time>2026-06-27T21:32:54Z</time></trkpt>
        </trkseg></trk></gpx>
        """

        let samples = try GPXParser().parse(data: Data(gpx.utf8)).samples

        XCTAssertEqual(samples.count, 4, "同秒采样点不得被丢弃")
        for (actual, expected) in zip(samples.map(\.elapsed), [0, 0.001, 0.002, 1]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(samples.last?.elapsed ?? 0, 1, accuracy: 0.01, "总时长不应被拉长")
    }

    /// 时间戳真正回退时仍需钳制，保证序列非递减，下游二分查找才成立。
    func testBackwardsTimestampsAreClampedToPreviousElapsed() throws {
        let gpx = """
        <gpx><trk><trkseg>
          <trkpt lat="35.0000" lon="139.0000"><time>2026-06-27T21:32:53Z</time></trkpt>
          <trkpt lat="35.0001" lon="139.0001"><time>2026-06-27T21:32:58Z</time></trkpt>
          <trkpt lat="35.0002" lon="139.0002"><time>2026-06-27T21:32:50Z</time></trkpt>
          <trkpt lat="35.0003" lon="139.0003"><time>2026-06-27T21:33:00Z</time></trkpt>
        </trkseg></trk></gpx>
        """

        let samples = try GPXParser().parse(data: Data(gpx.utf8)).samples

        let elapsed = samples.map(\.elapsed)
        XCTAssertEqual(elapsed, elapsed.sorted(), "elapsed 必须非递减，下游二分查找才成立")
        // 回退的那一点被钳到前一点之后，总时长仍由最后一个时间戳决定。
        XCTAssertEqual(samples.last?.elapsed ?? 0, 7, accuracy: 0.01)
    }

    func testTrackSegmentsDoNotBridgeDistanceOrInterpolation() throws {
        let gpx = """
        <gpx><trk>
          <trkseg>
            <trkpt lat="35.0000" lon="139.0000"><time>2026-06-27T21:32:53Z</time></trkpt>
            <trkpt lat="35.0001" lon="139.0000"><time>2026-06-27T21:32:54Z</time></trkpt>
          </trkseg>
          <trkseg>
            <trkpt lat="45.0000" lon="149.0000"><time>2026-06-27T21:33:03Z</time></trkpt>
            <trkpt lat="45.0001" lon="149.0000"><time>2026-06-27T21:33:04Z</time></trkpt>
          </trkseg>
        </trk></gpx>
        """

        let series = try GPXParser().parse(data: Data(gpx.utf8))

        XCTAssertEqual(series.samples.map(\.elapsed), [0, 1, 10, 11])
        XCTAssertEqual(series.samples.map(\.trackSegmentIndex), [0, 0, 1, 1])
        XCTAssertLessThan(series.samples.last?.distanceMeters ?? .infinity, 30)
        XCTAssertEqual(series.sample(at: 5).latitude ?? 0, 35.0001, accuracy: 0.000_001)
        XCTAssertEqual(series.sample(at: 5).longitude ?? 0, 139, accuracy: 0.000_001)
    }

    func testCyclingCadenceRemainsRPM() throws {
        let gpx = """
        <gpx><trk><type>Biking</type><trkseg>
          <trkpt lat="35" lon="139"><extensions><cadence>90</cadence></extensions></trkpt>
        </trkseg></trk></gpx>
        """

        let parsed = try GPXParser().parseActivity(data: Data(gpx.utf8))

        XCTAssertEqual(parsed.sport, .cycling)
        XCTAssertEqual(parsed.series.samples[0].cadence, 90)
    }
}

private let sampleGPX = """
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="COROS Wearables"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxdata="http://www.cluetrust.com/XML/GPXDATA/1/0"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <type>Running</type>
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
