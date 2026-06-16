import Foundation
@testable import OverlayCore
import XCTest

final class FITParserTests: XCTestCase {
    func testParsesStandardRecordMessages() throws {
        let fit = makeFITFile(records: [
            TestRecord(timestamp: 1_000_000, latitude: 35.0, longitude: 139.0, distanceMeters: 1200, speed: 3.0, heartRate: 151, cadence: 84),
            TestRecord(timestamp: 1_000_010, latitude: 35.0002, longitude: 139.0004, distanceMeters: 1235, speed: 3.4, heartRate: 154, cadence: 86)
        ])

        let series = try FITParser().parse(data: fit)
        let start = series.sample(at: 0)
        let end = series.sample(at: 10)

        XCTAssertEqual(series.samples.count, 11)
        XCTAssertEqual(start.elapsed, 0)
        XCTAssertEqual(end.elapsed, 10)
        XCTAssertEqual(start.latitude ?? 0, 35.0, accuracy: 0.00001)
        XCTAssertEqual(start.longitude ?? 0, 139.0, accuracy: 0.00001)
        XCTAssertEqual(start.distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(end.distanceMeters ?? -1, 35, accuracy: 0.001)
        XCTAssertEqual(end.speedMetersPerSecond ?? -1, 3.4, accuracy: 0.001)
        XCTAssertEqual(end.heartRate, 154)
        XCTAssertEqual(start.cadence, 168)
        XCTAssertEqual(end.cadence, 172)
    }

    func testInterpolatesSamples() throws {
        let fit = makeFITFile(records: [
            TestRecord(timestamp: 1_000_000, latitude: 35.0, longitude: 139.0, distanceMeters: 0, speed: 3.0, heartRate: 150, cadence: 80),
            TestRecord(timestamp: 1_000_010, latitude: 35.001, longitude: 139.002, distanceMeters: 30, speed: 4.0, heartRate: 160, cadence: 90)
        ])

        let sample = try FITParser().parse(data: fit).sample(at: 5)

        XCTAssertEqual(sample.distanceMeters ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(sample.speedMetersPerSecond ?? -1, 3.5, accuracy: 0.001)
        XCTAssertEqual(sample.heartRate, 160)
        XCTAssertEqual(sample.cadence, 180)
    }

    func testRejectsCRCByDefault() throws {
        var fit = makeFITFile(records: [
            TestRecord(timestamp: 1_000_000, latitude: 35.0, longitude: 139.0, distanceMeters: 0, speed: 3.0, heartRate: 150, cadence: 80)
        ])
        fit[fit.count - 1] ^= 0xFF

        XCTAssertThrowsError(try FITParser().parse(data: fit)) { error in
            guard case FITError.fileCRCMismatch = error else {
                return XCTFail("Expected file CRC mismatch, got \(error)")
            }
        }
    }
}

private struct TestRecord {
    var timestamp: UInt32
    var latitude: Double
    var longitude: Double
    var distanceMeters: Double
    var speed: Double
    var heartRate: UInt8
    var cadence: UInt8
}

private func makeFITFile(records: [TestRecord]) -> Data {
    var content = Data()

    content.append(0x40)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(20, to: &content)
    content.append(7)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [0, 4, 0x85])
    content.append(contentsOf: [1, 4, 0x85])
    content.append(contentsOf: [5, 4, 0x86])
    content.append(contentsOf: [6, 2, 0x84])
    content.append(contentsOf: [3, 1, 0x02])
    content.append(contentsOf: [4, 1, 0x02])

    for record in records {
        content.append(0x00)
        appendUInt32(record.timestamp, to: &content)
        appendInt32(semicircles(record.latitude), to: &content)
        appendInt32(semicircles(record.longitude), to: &content)
        appendUInt32(UInt32((record.distanceMeters * 100).rounded()), to: &content)
        appendUInt16(UInt16((record.speed * 1000).rounded()), to: &content)
        content.append(record.heartRate)
        content.append(record.cadence)
    }

    var file = Data()
    file.append(12)
    file.append(0x10)
    appendUInt16(0, to: &file)
    appendUInt32(UInt32(content.count), to: &file)
    file.append(contentsOf: [UInt8(ascii: "."), UInt8(ascii: "F"), UInt8(ascii: "I"), UInt8(ascii: "T")])
    file.append(content)
    appendUInt16(FITCRC.compute(file), to: &file)
    return file
}

private func semicircles(_ degrees: Double) -> Int32 {
    Int32((degrees / 180 * 2_147_483_648).rounded())
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}

private func appendInt32(_ value: Int32, to data: inout Data) {
    appendUInt32(UInt32(bitPattern: value), to: &data)
}
