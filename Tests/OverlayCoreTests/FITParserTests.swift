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

    func testUsesTimerStartEventBeforeFirstRecordToAvoidStartupDelay() throws {
        var content = Data()
        appendEventDefinition(localMessageType: 1, to: &content)
        appendStandardRecordDefinition(localMessageType: 0, to: &content)
        appendTimerStartEvent(timestamp: 1_000_000, localMessageType: 1, to: &content)
        appendRecord(
            TestRecord(timestamp: 1_000_008, latitude: 35.0, longitude: 139.0, distanceMeters: 1200, speed: 3.0, heartRate: 151, cadence: 84),
            localMessageType: 0,
            to: &content
        )
        appendRecord(
            TestRecord(timestamp: 1_000_010, latitude: 35.0002, longitude: 139.0004, distanceMeters: 1206, speed: 3.4, heartRate: 154, cadence: 86),
            localMessageType: 0,
            to: &content
        )

        let series = try FITParser().parse(data: makeFITFile(content: content))
        let start = series.sample(at: 0)
        let halfway = series.sample(at: 4)
        let firstRecordTime = series.sample(at: 8)

        XCTAssertEqual(series.samples.first?.elapsed, 0)
        XCTAssertEqual(start.speedMetersPerSecond ?? -1, 3.0, accuracy: 0.001)
        XCTAssertEqual(start.distanceMeters ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(start.cadence, 0)
        XCTAssertEqual(halfway.cadence, 84)
        XCTAssertEqual(firstRecordTime.heartRate, 151)
        XCTAssertEqual(firstRecordTime.cadence, 168)
    }

    func testDerivesPaceImmediatelyFromStartupDistanceBeforeFirstRecord() throws {
        var content = Data()
        appendEventDefinition(localMessageType: 1, to: &content)
        appendStandardRecordDefinition(localMessageType: 0, to: &content)
        appendTimerStartEvent(timestamp: 1_000_000, localMessageType: 1, to: &content)
        appendRecord(
            TestRecord(timestamp: 1_000_008, latitude: 35.0, longitude: 139.0, distanceMeters: 40, speed: 0, heartRate: 151, cadence: 84),
            localMessageType: 0,
            to: &content
        )
        appendRecord(
            TestRecord(timestamp: 1_000_010, latitude: 35.0002, longitude: 139.0004, distanceMeters: 50, speed: 0, heartRate: 154, cadence: 86),
            localMessageType: 0,
            to: &content
        )

        let series = try FITParser().parse(data: makeFITFile(content: content))

        XCTAssertEqual(series.sample(at: 1).distanceMeters ?? -1, 5, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 1).speedMetersPerSecond ?? -1, 0.3)
        XCTAssertEqual(series.sample(at: 4).distanceMeters ?? -1, 20, accuracy: 0.001)
        XCTAssertGreaterThan(series.sample(at: 4).speedMetersPerSecond ?? -1, series.sample(at: 1).speedMetersPerSecond ?? 0)
        XCTAssertEqual(series.sample(at: 8).speedMetersPerSecond ?? -1, 5, accuracy: 0.001)
    }

    func testUsesSessionStartTimeWhenTimerStartEventIsMissing() throws {
        var content = Data()
        appendSessionDefinition(localMessageType: 2, to: &content)
        appendStandardRecordDefinition(localMessageType: 0, to: &content)
        appendSession(timestamp: 1_000_030, startTime: 1_000_000, localMessageType: 2, to: &content)
        appendRecord(
            TestRecord(timestamp: 1_000_006, latitude: 35.0, longitude: 139.0, distanceMeters: 800, speed: 3.2, heartRate: 149, cadence: 82),
            localMessageType: 0,
            to: &content
        )

        let series = try FITParser().parse(data: makeFITFile(content: content))

        XCTAssertEqual(series.samples.first?.elapsed, 0)
        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 3.2, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 6).heartRate, 149)
    }

    func testParsesFractionalCadenceAsFractionalRPMBeforeConvertingToSPM() throws {
        var content = Data()
        appendFractionalCadenceRecordDefinition(localMessageType: 0, to: &content)
        appendFractionalCadenceRecord(timestamp: 1_000_000, cadence: 80, fractionalCadenceRaw: 64, localMessageType: 0, to: &content)

        let sample = try FITParser().parse(data: makeFITFile(content: content)).sample(at: 0)

        XCTAssertEqual(sample.cadence, 161)
    }

    func testParsesPowerAndStepLengthRecordFields() throws {
        var content = Data()
        appendExtendedRecordDefinition(localMessageType: 0, to: &content)
        appendExtendedRecord(
            TestRecord(
                timestamp: 1_000_000,
                latitude: 35.0,
                longitude: 139.0,
                distanceMeters: 0,
                speed: 3.0,
                heartRate: 150,
                cadence: 80,
                powerWatts: 286,
                stepLengthRaw: 12_340
            ),
            localMessageType: 0,
            to: &content
        )

        let sample = try FITParser().parse(data: makeFITFile(content: content)).sample(at: 0)

        XCTAssertEqual(sample.powerWatts, 286)
        XCTAssertEqual(sample.stepLengthMeters ?? -1, 1.234, accuracy: 0.001)
    }

    func testInterpolatesCurrentCaloriesFromLapTotals() throws {
        var content = Data()
        appendStandardRecordDefinition(localMessageType: 0, to: &content)
        appendLapDefinition(localMessageType: 1, to: &content)
        appendRecord(
            TestRecord(timestamp: 1_000_000, latitude: 35.0, longitude: 139.0, distanceMeters: 0, speed: 3.0, heartRate: 150, cadence: 80),
            localMessageType: 0,
            to: &content
        )
        appendRecord(
            TestRecord(timestamp: 1_000_005, latitude: 35.00005, longitude: 139.00005, distanceMeters: 15, speed: 3.0, heartRate: 151, cadence: 81),
            localMessageType: 0,
            to: &content
        )
        appendRecord(
            TestRecord(timestamp: 1_000_010, latitude: 35.0001, longitude: 139.0001, distanceMeters: 30, speed: 3.0, heartRate: 151, cadence: 81),
            localMessageType: 0,
            to: &content
        )
        appendLap(timestamp: 1_000_005, totalCalories: 50, localMessageType: 1, to: &content)
        appendLap(timestamp: 1_000_010, totalCalories: 70, localMessageType: 1, to: &content)

        let series = try FITParser().parse(data: makeFITFile(content: content))

        XCTAssertEqual(series.sample(at: 0).totalCalories ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).totalCalories ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 7).totalCalories ?? -1, 78, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 10).totalCalories ?? -1, 120, accuracy: 0.001)
    }

    func testParsesStandardCompressedSpeedDistanceRecords() throws {
        var content = Data()
        appendCompressedSpeedDistanceRecordDefinition(localMessageType: 0, to: &content)
        appendCompressedSpeedDistanceRecord(
            timestamp: 1_000_000,
            speedMetersPerSecond: 3.25,
            accumulatedDistanceMeters: 0,
            localMessageType: 0,
            to: &content
        )
        appendCompressedSpeedDistanceRecord(
            timestamp: 1_000_002,
            speedMetersPerSecond: 3.5,
            accumulatedDistanceMeters: 4,
            localMessageType: 0,
            to: &content
        )

        let series = try FITParser().parse(data: makeFITFile(content: content))

        XCTAssertEqual(series.sample(at: 0).speedMetersPerSecond ?? -1, 3.25, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).speedMetersPerSecond ?? -1, 3.5, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 4, accuracy: 0.001)
    }

    func testSkipsDeveloperFieldValuesInRecordMessages() throws {
        var content = Data()
        appendDeveloperRecordDefinition(localMessageType: 0, to: &content)
        appendRecordWithDeveloperByte(
            TestRecord(timestamp: 1_000_000, latitude: 35.0, longitude: 139.0, distanceMeters: 0, speed: 3.0, heartRate: 150, cadence: 80),
            localMessageType: 0,
            developerValue: 45,
            to: &content
        )
        appendRecordWithDeveloperByte(
            TestRecord(timestamp: 1_000_002, latitude: 35.0001, longitude: 139.0001, distanceMeters: 6, speed: 3.2, heartRate: 151, cadence: 81),
            localMessageType: 0,
            developerValue: 46,
            to: &content
        )

        let series = try FITParser().parse(data: makeFITFile(content: content))

        XCTAssertEqual(series.samples.count, 3)
        XCTAssertEqual(series.sample(at: 2).distanceMeters ?? -1, 6, accuracy: 0.001)
        XCTAssertEqual(series.sample(at: 2).heartRate, 151)
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
    var powerWatts: UInt16? = nil
    var stepLengthRaw: UInt16? = nil
}

private func makeFITFile(records: [TestRecord]) -> Data {
    var content = Data()
    appendStandardRecordDefinition(localMessageType: 0, to: &content)

    for record in records {
        appendRecord(record, localMessageType: 0, to: &content)
    }

    return makeFITFile(content: content)
}

private func makeFITFile(content: Data) -> Data {
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

private func appendStandardRecordDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
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
}

private func appendDeveloperRecordDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x60 | localMessageType)
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
    content.append(1)
    content.append(contentsOf: [0, 1, 0])
}

private func appendCompressedSpeedDistanceRecordDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(20, to: &content)
    content.append(2)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [8, 3, 0x0D])
}

private func appendExtendedRecordDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(20, to: &content)
    content.append(9)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [0, 4, 0x85])
    content.append(contentsOf: [1, 4, 0x85])
    content.append(contentsOf: [5, 4, 0x86])
    content.append(contentsOf: [6, 2, 0x84])
    content.append(contentsOf: [3, 1, 0x02])
    content.append(contentsOf: [4, 1, 0x02])
    content.append(contentsOf: [7, 2, 0x84])
    content.append(contentsOf: [85, 2, 0x84])
}

private func appendLapDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(19, to: &content)
    content.append(2)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [11, 2, 0x84])
}

private func appendEventDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(21, to: &content)
    content.append(3)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [0, 1, 0x00])
    content.append(contentsOf: [1, 1, 0x00])
}

private func appendSessionDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(18, to: &content)
    content.append(2)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [2, 4, 0x86])
}

private func appendFractionalCadenceRecordDefinition(localMessageType: UInt8, to content: inout Data) {
    content.append(0x40 | localMessageType)
    content.append(0x00)
    content.append(0x00)
    appendUInt16(20, to: &content)
    content.append(3)
    content.append(contentsOf: [253, 4, 0x86])
    content.append(contentsOf: [4, 1, 0x02])
    content.append(contentsOf: [53, 1, 0x02])
}

private func appendTimerStartEvent(timestamp: UInt32, localMessageType: UInt8, to content: inout Data) {
    content.append(localMessageType)
    appendUInt32(timestamp, to: &content)
    content.append(0)
    content.append(0)
}

private func appendSession(timestamp: UInt32, startTime: UInt32, localMessageType: UInt8, to content: inout Data) {
    content.append(localMessageType)
    appendUInt32(timestamp, to: &content)
    appendUInt32(startTime, to: &content)
}

private func appendFractionalCadenceRecord(
    timestamp: UInt32,
    cadence: UInt8,
    fractionalCadenceRaw: UInt8,
    localMessageType: UInt8,
    to content: inout Data
) {
    content.append(localMessageType)
    appendUInt32(timestamp, to: &content)
    content.append(cadence)
    content.append(fractionalCadenceRaw)
}

private func appendRecord(_ record: TestRecord, localMessageType: UInt8, to content: inout Data) {
    content.append(localMessageType)
    appendUInt32(record.timestamp, to: &content)
    appendInt32(semicircles(record.latitude), to: &content)
    appendInt32(semicircles(record.longitude), to: &content)
    appendUInt32(UInt32((record.distanceMeters * 100).rounded()), to: &content)
    appendUInt16(UInt16((record.speed * 1000).rounded()), to: &content)
    content.append(record.heartRate)
    content.append(record.cadence)
}

private func appendExtendedRecord(_ record: TestRecord, localMessageType: UInt8, to content: inout Data) {
    appendRecord(record, localMessageType: localMessageType, to: &content)
    appendUInt16(record.powerWatts ?? 0xFFFF, to: &content)
    appendUInt16(record.stepLengthRaw ?? 0xFFFF, to: &content)
}

private func appendLap(timestamp: UInt32, totalCalories: UInt16, localMessageType: UInt8, to content: inout Data) {
    content.append(localMessageType)
    appendUInt32(timestamp, to: &content)
    appendUInt16(totalCalories, to: &content)
}

private func appendRecordWithDeveloperByte(
    _ record: TestRecord,
    localMessageType: UInt8,
    developerValue: UInt8,
    to content: inout Data
) {
    appendRecord(record, localMessageType: localMessageType, to: &content)
    content.append(developerValue)
}

private func appendCompressedSpeedDistanceRecord(
    timestamp: UInt32,
    speedMetersPerSecond: Double,
    accumulatedDistanceMeters: Double,
    localMessageType: UInt8,
    to content: inout Data
) {
    content.append(localMessageType)
    appendUInt32(timestamp, to: &content)
    content.append(contentsOf: compressedSpeedDistance(
        speedMetersPerSecond: speedMetersPerSecond,
        accumulatedDistanceMeters: accumulatedDistanceMeters
    ))
}

private func compressedSpeedDistance(speedMetersPerSecond: Double, accumulatedDistanceMeters: Double) -> [UInt8] {
    let speedRaw = UInt32((speedMetersPerSecond * 100).rounded()) & 0x0FFF
    let distanceRaw = (UInt32((accumulatedDistanceMeters * 16).rounded()) & 0x0FFF) << 12
    let raw = speedRaw | distanceRaw
    return [
        UInt8(raw & 0xFF),
        UInt8((raw >> 8) & 0xFF),
        UInt8((raw >> 16) & 0xFF)
    ]
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
