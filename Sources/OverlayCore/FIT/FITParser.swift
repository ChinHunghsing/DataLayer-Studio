import Foundation

struct FITFieldDefinition {
    var number: UInt8
    var size: UInt8
    var baseType: UInt8
}

struct FITLocalMessageDefinition {
    var endian: FITEndian
    var globalMessageNumber: UInt16
    var fields: [FITFieldDefinition]
}

struct RawFITRecord {
    var timestamp: UInt32?
    var latitude: Double?
    var longitude: Double?
    var altitudeMeters: Double?
    var heartRate: Int?
    var cadence: Int?
    var distanceMeters: Double?
    var speedMetersPerSecond: Double?
    var powerWatts: Int?
    var temperatureCelsius: Int?
}

public final class FITParser {
    private let validateCRC: Bool

    public init(validateCRC: Bool = true) {
        self.validateCRC = validateCRC
    }

    public func parse(url: URL) throws -> TelemetrySeries {
        try parse(data: Data(contentsOf: url))
    }

    public func parse(data: Data) throws -> TelemetrySeries {
        guard data.count >= 14 else { throw FITError.fileTooSmall }

        let headerSize = Int(data[0])
        guard headerSize >= 12 else { throw FITError.unsupportedHeaderSize(headerSize) }
        guard data.count >= headerSize + 2 else { throw FITError.truncatedFile(expected: headerSize + 2, actual: data.count) }
        guard data[8] == UInt8(ascii: "."), data[9] == UInt8(ascii: "F"),
              data[10] == UInt8(ascii: "I"), data[11] == UInt8(ascii: "T") else {
            throw FITError.invalidSignature
        }

        let dataSize = Int(data.uint32(at: 4, endian: .little))
        let dataStart = headerSize
        let dataEnd = dataStart + dataSize
        let expectedSize = dataEnd + 2
        guard data.count >= expectedSize else {
            throw FITError.truncatedFile(expected: expectedSize, actual: data.count)
        }

        if validateCRC {
            if headerSize >= 14 {
                let expectedHeaderCRC = data.uint16(at: headerSize - 2, endian: .little)
                let actualHeaderCRC = FITCRC.compute(data[0..<(headerSize - 2)])
                guard expectedHeaderCRC == actualHeaderCRC else {
                    throw FITError.headerCRCMismatch(expected: expectedHeaderCRC, actual: actualHeaderCRC)
                }
            }

            let expectedFileCRC = data.uint16(at: dataEnd, endian: .little)
            let actualFileCRC = FITCRC.compute(data[0..<dataEnd])
            guard expectedFileCRC == actualFileCRC else {
                throw FITError.fileCRCMismatch(expected: expectedFileCRC, actual: actualFileCRC)
            }
        }

        var reader = ByteReader(data: data, offset: dataStart, endOffset: dataEnd)
        var definitions: [UInt8: FITLocalMessageDefinition] = [:]
        var records: [RawFITRecord] = []
        var lastTimestamp: UInt32?

        while !reader.isAtEnd {
            let recordOffset = reader.offset
            let header = try reader.readUInt8()

            if (header & 0x80) != 0 {
                let localMessageType = (header >> 5) & 0x03
                let compressedOffset = UInt32(header & 0x1F)
                let compressedTimestamp = expandedTimestamp(lastTimestamp: lastTimestamp, offset: compressedOffset)
                guard let definition = definitions[localMessageType] else {
                    throw FITError.missingDefinition(localMessageType: localMessageType)
                }
                let parsed = try parseDataMessage(
                    definition: definition,
                    reader: &reader,
                    compressedTimestamp: compressedTimestamp
                )
                if let timestamp = parsed.timestamp {
                    lastTimestamp = timestamp
                }
                if definition.globalMessageNumber == 20, parsed.hasTelemetryPayload {
                    records.append(parsed)
                }
            } else {
                let localMessageType = header & 0x0F
                let isDefinition = (header & 0x40) != 0
                let hasDeveloperData = (header & 0x20) != 0

                if isDefinition {
                    definitions[localMessageType] = try parseDefinition(
                        reader: &reader,
                        hasDeveloperData: hasDeveloperData
                    )
                } else {
                    guard let definition = definitions[localMessageType] else {
                        throw FITError.missingDefinition(localMessageType: localMessageType)
                    }
                    let parsed = try parseDataMessage(
                        definition: definition,
                        reader: &reader,
                        compressedTimestamp: nil
                    )
                    if let timestamp = parsed.timestamp {
                        lastTimestamp = timestamp
                    }
                    if definition.globalMessageNumber == 20, parsed.hasTelemetryPayload {
                        records.append(parsed)
                    }
                }
            }

            guard reader.offset > recordOffset else {
                throw FITError.malformedRecord(offset: recordOffset)
            }
        }

        guard !records.isEmpty else { throw FITError.noRecordMessages }
        return TelemetrySeries(samples: samples(from: records))
    }

    private func parseDefinition(
        reader: inout ByteReader,
        hasDeveloperData: Bool
    ) throws -> FITLocalMessageDefinition {
        _ = try reader.readUInt8()
        let architecture = try reader.readUInt8()
        let endian: FITEndian = architecture == 0 ? .little : .big
        let globalMessageNumber = try reader.readUInt16(endian: endian)
        let fieldCount = Int(try reader.readUInt8())
        var fields: [FITFieldDefinition] = []
        fields.reserveCapacity(fieldCount)

        for _ in 0..<fieldCount {
            fields.append(FITFieldDefinition(
                number: try reader.readUInt8(),
                size: try reader.readUInt8(),
                baseType: try reader.readUInt8()
            ))
        }

        if hasDeveloperData {
            let developerFieldCount = Int(try reader.readUInt8())
            try reader.skip(count: developerFieldCount * 3)
        }

        return FITLocalMessageDefinition(
            endian: endian,
            globalMessageNumber: globalMessageNumber,
            fields: fields
        )
    }

    private func parseDataMessage(
        definition: FITLocalMessageDefinition,
        reader: inout ByteReader,
        compressedTimestamp: UInt32?
    ) throws -> RawFITRecord {
        var record = RawFITRecord(timestamp: compressedTimestamp)

        for field in definition.fields {
            let bytes = try reader.readBytes(count: Int(field.size))
            guard let value = FITFieldDecoder.number(
                bytes: bytes,
                baseType: field.baseType,
                endian: definition.endian
            ) else {
                continue
            }

            if field.number == 253 {
                record.timestamp = UInt32(value)
            }

            guard definition.globalMessageNumber == 20 else { continue }

            switch field.number {
            case 0:
                record.latitude = semicirclesToDegrees(value)
            case 1:
                record.longitude = semicirclesToDegrees(value)
            case 2:
                if record.altitudeMeters == nil {
                    record.altitudeMeters = (value / 5) - 500
                }
            case 3:
                record.heartRate = Int(value)
            case 4:
                record.cadence = Int(value)
            case 5:
                record.distanceMeters = value / 100
            case 6:
                if record.speedMetersPerSecond == nil {
                    record.speedMetersPerSecond = value / 1000
                }
            case 7:
                record.powerWatts = Int(value)
            case 13:
                record.temperatureCelsius = Int(value)
            case 73:
                record.speedMetersPerSecond = value / 1000
            case 78:
                record.altitudeMeters = (value / 5) - 500
            default:
                continue
            }
        }

        return record
    }

    private func samples(from records: [RawFITRecord]) -> [TelemetrySample] {
        let timestampedRecords = records.filter { $0.timestamp != nil }
        let sourceRecords = timestampedRecords.isEmpty ? records : timestampedRecords
        let firstTimestamp = sourceRecords.compactMap(\.timestamp).first
        let fitEpoch = Date(timeIntervalSince1970: 631_065_600)

        return sourceRecords.enumerated().map { index, record in
            let elapsed: TimeInterval
            let date: Date?
            if let timestamp = record.timestamp, let firstTimestamp {
                elapsed = TimeInterval(timestamp - firstTimestamp)
                date = fitEpoch.addingTimeInterval(TimeInterval(timestamp))
            } else {
                elapsed = TimeInterval(index)
                date = nil
            }

            return TelemetrySample(
                elapsed: elapsed,
                date: date,
                latitude: record.latitude,
                longitude: record.longitude,
                altitudeMeters: record.altitudeMeters,
                heartRate: record.heartRate,
                cadence: record.cadence.map { $0 * 2 },
                distanceMeters: record.distanceMeters,
                speedMetersPerSecond: record.speedMetersPerSecond,
                powerWatts: record.powerWatts,
                temperatureCelsius: record.temperatureCelsius
            )
        }
    }

    private func semicirclesToDegrees(_ value: Double) -> Double {
        value * 180 / 2_147_483_648
    }

    private func expandedTimestamp(lastTimestamp: UInt32?, offset: UInt32) -> UInt32? {
        guard let lastTimestamp else { return nil }
        var timestamp = (lastTimestamp & ~0x1F) + offset
        if timestamp < lastTimestamp {
            timestamp += 0x20
        }
        return timestamp
    }
}

private extension RawFITRecord {
    var hasTelemetryPayload: Bool {
        timestamp != nil
            || latitude != nil
            || longitude != nil
            || altitudeMeters != nil
            || heartRate != nil
            || cadence != nil
            || distanceMeters != nil
            || speedMetersPerSecond != nil
            || powerWatts != nil
            || temperatureCelsius != nil
    }
}
