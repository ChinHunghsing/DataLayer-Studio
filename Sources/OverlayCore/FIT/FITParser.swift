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
    var developerFieldSizes: [UInt8]
}

struct RawFITRecord {
    var timestamp: UInt32?
    var latitude: Double?
    var longitude: Double?
    var altitudeMeters: Double?
    var heartRate: Int?
    var cadence: Int?
    var fractionalCadence: Double?
    var distanceMeters: Double?
    var speedMetersPerSecond: Double?
    var powerWatts: Int?
    var stepLengthMeters: Double?
    var temperatureCelsius: Int?
}

struct RawFITEvent {
    var timestamp: UInt32?
    var event: Int?
    var eventType: Int?

    var isTimerStart: Bool {
        event == 0 && eventType == 0
    }
}

struct RawFITSession {
    var timestamp: UInt32?
    var startTime: UInt32?
    var totalCalories: Int?
}

struct RawFITLap {
    var timestamp: UInt32?
    var totalCalories: Int?
}

struct ParsedFITMessage {
    var timestamp: UInt32?
    var record: RawFITRecord?
    var event: RawFITEvent?
    var session: RawFITSession?
    var lap: RawFITLap?
}

private struct CaloriePoint {
    var elapsed: TimeInterval
    var calories: Double
}

private struct CompressedDistanceAccumulator {
    private var previousRaw: UInt16?
    private var accumulatedRaw: UInt64 = 0

    mutating func meters(for raw: UInt16) -> Double {
        let masked = raw & 0x0FFF
        guard let previousRaw else {
            previousRaw = masked
            accumulatedRaw = UInt64(masked)
            return Double(accumulatedRaw) / 16
        }

        let previousMasked = previousRaw & 0x0FFF
        let delta = masked >= previousMasked
            ? UInt64(masked - previousMasked)
            : UInt64(masked) + 0x1000 - UInt64(previousMasked)
        accumulatedRaw += delta
        self.previousRaw = masked
        return Double(accumulatedRaw) / 16
    }
}

public final class FITParser {
    private let validateCRC: Bool
    private let maximumPlausibleStartupSpeedMetersPerSecond = 12.0

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
        var laps: [RawFITLap] = []
        var sessions: [RawFITSession] = []
        var timerStartTimestamps: [UInt32] = []
        var sessionStartTimestamps: [UInt32] = []
        var compressedDistanceAccumulator = CompressedDistanceAccumulator()
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
                    compressedTimestamp: compressedTimestamp,
                    compressedDistanceAccumulator: &compressedDistanceAccumulator
                )
                if let timestamp = parsed.timestamp {
                    lastTimestamp = timestamp
                }
                append(
                    parsed: parsed,
                    definition: definition,
                    records: &records,
                    laps: &laps,
                    sessions: &sessions,
                    timerStartTimestamps: &timerStartTimestamps,
                    sessionStartTimestamps: &sessionStartTimestamps
                )
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
                        compressedTimestamp: nil,
                        compressedDistanceAccumulator: &compressedDistanceAccumulator
                    )
                    if let timestamp = parsed.timestamp {
                        lastTimestamp = timestamp
                    }
                    append(
                        parsed: parsed,
                        definition: definition,
                        records: &records,
                        laps: &laps,
                        sessions: &sessions,
                        timerStartTimestamps: &timerStartTimestamps,
                        sessionStartTimestamps: &sessionStartTimestamps
                    )
                }
            }

            guard reader.offset > recordOffset else {
                throw FITError.malformedRecord(offset: recordOffset)
            }
        }

        guard !records.isEmpty else { throw FITError.noRecordMessages }
        let activityStartTimestamp = activityStartTimestamp(
            records: records,
            timerStartTimestamps: timerStartTimestamps,
            sessionStartTimestamps: sessionStartTimestamps
        )
        return TelemetrySeries(samples: samples(
            from: records,
            activityStartTimestamp: activityStartTimestamp,
            caloriePoints: caloriePoints(
                laps: laps,
                sessions: sessions,
                records: records,
                activityStartTimestamp: activityStartTimestamp
            )
        ))
    }

    private func append(
        parsed: ParsedFITMessage,
        definition: FITLocalMessageDefinition,
        records: inout [RawFITRecord],
        laps: inout [RawFITLap],
        sessions: inout [RawFITSession],
        timerStartTimestamps: inout [UInt32],
        sessionStartTimestamps: inout [UInt32]
    ) {
        switch definition.globalMessageNumber {
        case 20:
            if let record = parsed.record, record.hasTelemetryPayload {
                records.append(record)
            }
        case 21:
            if let event = parsed.event, event.isTimerStart, let timestamp = event.timestamp {
                timerStartTimestamps.append(timestamp)
            }
        case 18:
            if let session = parsed.session {
                sessions.append(session)
            }
            if let startTime = parsed.session?.startTime {
                sessionStartTimestamps.append(startTime)
            }
        case 19:
            if let lap = parsed.lap, lap.timestamp != nil || lap.totalCalories != nil {
                laps.append(lap)
            }
        default:
            return
        }
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

        var developerFieldSizes: [UInt8] = []
        if hasDeveloperData {
            let developerFieldCount = Int(try reader.readUInt8())
            developerFieldSizes.reserveCapacity(developerFieldCount)
            for _ in 0..<developerFieldCount {
                _ = try reader.readUInt8()
                developerFieldSizes.append(try reader.readUInt8())
                _ = try reader.readUInt8()
            }
        }

        return FITLocalMessageDefinition(
            endian: endian,
            globalMessageNumber: globalMessageNumber,
            fields: fields,
            developerFieldSizes: developerFieldSizes
        )
    }

    private func parseDataMessage(
        definition: FITLocalMessageDefinition,
        reader: inout ByteReader,
        compressedTimestamp: UInt32?,
        compressedDistanceAccumulator: inout CompressedDistanceAccumulator
    ) throws -> ParsedFITMessage {
        var timestamp = compressedTimestamp
        var record = RawFITRecord(timestamp: compressedTimestamp)
        var event = RawFITEvent(timestamp: compressedTimestamp)
        var session = RawFITSession(timestamp: compressedTimestamp)
        var lap = RawFITLap(timestamp: compressedTimestamp)

        for field in definition.fields {
            let bytes = try reader.readBytes(count: Int(field.size))
            if definition.globalMessageNumber == 20,
               field.number == 8,
               let compressed = compressedSpeedDistance(bytes: bytes, accumulator: &compressedDistanceAccumulator) {
                if record.speedMetersPerSecond == nil {
                    record.speedMetersPerSecond = compressed.speedMetersPerSecond
                }
                if record.distanceMeters == nil {
                    record.distanceMeters = compressed.distanceMeters
                }
                continue
            }

            guard let value = FITFieldDecoder.number(
                bytes: bytes,
                baseType: field.baseType,
                endian: definition.endian
            ) else {
                continue
            }

            if field.number == 253 {
                timestamp = UInt32(value)
            }

            switch definition.globalMessageNumber {
            case 20:
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
                case 53:
                    record.fractionalCadence = value / 128
                case 73:
                    record.speedMetersPerSecond = value / 1000
                case 78:
                    record.altitudeMeters = (value / 5) - 500
                case 85:
                    record.stepLengthMeters = value / 10_000
                default:
                    continue
                }
            case 21:
                switch field.number {
                case 0:
                    event.event = Int(value)
                case 1:
                    event.eventType = Int(value)
                default:
                    continue
                }
            case 18:
                switch field.number {
                case 2:
                    session.startTime = UInt32(value)
                case 11:
                    session.totalCalories = Int(value)
                default:
                    continue
                }
            case 19:
                switch field.number {
                case 11:
                    lap.totalCalories = Int(value)
                default:
                    continue
                }
            default:
                continue
            }
        }

        for size in definition.developerFieldSizes {
            try reader.skip(count: Int(size))
        }

        record.timestamp = timestamp
        event.timestamp = timestamp
        session.timestamp = timestamp
        lap.timestamp = timestamp

        return ParsedFITMessage(
            timestamp: timestamp,
            record: definition.globalMessageNumber == 20 ? record : nil,
            event: definition.globalMessageNumber == 21 ? event : nil,
            session: definition.globalMessageNumber == 18 ? session : nil,
            lap: definition.globalMessageNumber == 19 ? lap : nil
        )
    }

    private func samples(
        from records: [RawFITRecord],
        activityStartTimestamp: UInt32?,
        caloriePoints: [CaloriePoint]
    ) -> [TelemetrySample] {
        let timestampedRecords = records.filter { $0.timestamp != nil }
        let sourceRecords = timestampedRecords.isEmpty ? records : timestampedRecords
        let firstTimestamp = activityStartTimestamp ?? sourceRecords.compactMap(\.timestamp).first
        let fitEpoch = Date(timeIntervalSince1970: 631_065_600)

        var samples = sourceRecords.enumerated().map { index, record in
            let elapsed: TimeInterval
            let date: Date?
            if let timestamp = record.timestamp, let firstTimestamp {
                elapsed = max(0, TimeInterval(Int64(timestamp) - Int64(firstTimestamp)))
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
                cadence: cadenceStepsPerMinute(record),
                distanceMeters: record.distanceMeters,
                speedMetersPerSecond: record.speedMetersPerSecond,
                powerWatts: record.powerWatts,
                totalCalories: calories(at: elapsed, points: caloriePoints),
                stepLengthMeters: record.stepLengthMeters,
                temperatureCelsius: record.temperatureCelsius
            )
        }

        if let activityStartTimestamp,
           let firstRecord = sourceRecords.first,
           let firstRecordTimestamp = firstRecord.timestamp,
           firstRecordTimestamp > activityStartTimestamp,
           let firstSample = samples.first,
           firstSample.elapsed > 0 {
            samples.insert(TelemetrySample(
                elapsed: 0,
                date: fitEpoch.addingTimeInterval(TimeInterval(activityStartTimestamp)),
                latitude: firstRecord.latitude,
                longitude: firstRecord.longitude,
                altitudeMeters: firstRecord.altitudeMeters,
                heartRate: firstRecord.heartRate,
                cadence: cadenceStepsPerMinute(firstRecord).map { _ in 0 },
                distanceMeters: syntheticStartDistance(firstRecord, elapsed: firstSample.elapsed),
                speedMetersPerSecond: firstRecord.speedMetersPerSecond,
                powerWatts: firstRecord.powerWatts,
                totalCalories: calories(at: 0, points: caloriePoints),
                stepLengthMeters: firstRecord.stepLengthMeters,
                temperatureCelsius: firstRecord.temperatureCelsius
            ), at: 0)
        }

        return samples
    }

    private func caloriePoints(
        laps: [RawFITLap],
        sessions: [RawFITSession],
        records: [RawFITRecord],
        activityStartTimestamp: UInt32?
    ) -> [CaloriePoint] {
        guard let activityStartTimestamp = activityStartTimestamp ?? records.compactMap(\.timestamp).min() else {
            return []
        }
        var points = [CaloriePoint(elapsed: 0, calories: 0)]
        var cumulativeCalories = 0.0

        for lap in laps.sorted(by: { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }) {
            guard let timestamp = lap.timestamp,
                  timestamp >= activityStartTimestamp,
                  let lapCalories = lap.totalCalories,
                  lapCalories >= 0 else {
                continue
            }

            cumulativeCalories += Double(lapCalories)
            let elapsed = TimeInterval(Int64(timestamp) - Int64(activityStartTimestamp))
            guard elapsed >= 0 else { continue }
            if let last = points.last, abs(last.elapsed - elapsed) < 0.000_001 {
                points[points.count - 1] = CaloriePoint(elapsed: elapsed, calories: cumulativeCalories)
            } else {
                points.append(CaloriePoint(elapsed: elapsed, calories: cumulativeCalories))
            }
        }

        if points.count > 1 {
            return points
        }

        guard let totalCalories = sessions.compactMap(\.totalCalories).last,
              totalCalories > 0 else {
            return []
        }

        let sessionEndTimestamp = sessions.compactMap(\.timestamp).max()
        let recordEndTimestamp = records.compactMap(\.timestamp).max()
        guard let endTimestamp = sessionEndTimestamp ?? recordEndTimestamp,
              endTimestamp > activityStartTimestamp else {
            return []
        }

        return [
            CaloriePoint(elapsed: 0, calories: 0),
            CaloriePoint(
                elapsed: TimeInterval(Int64(endTimestamp) - Int64(activityStartTimestamp)),
                calories: Double(totalCalories)
            )
        ]
    }

    private func calories(at elapsed: TimeInterval, points: [CaloriePoint]) -> Double? {
        guard points.count > 1 else { return nil }
        if elapsed <= points[0].elapsed {
            return points[0].calories
        }
        if elapsed >= points[points.count - 1].elapsed {
            return points[points.count - 1].calories
        }

        var low = 0
        var high = points.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if points[mid].elapsed <= elapsed {
                low = mid
            } else {
                high = mid
            }
        }

        let a = points[low]
        let b = points[high]
        let span = max(b.elapsed - a.elapsed, 0.000_001)
        let fraction = min(1, max(0, (elapsed - a.elapsed) / span))
        return a.calories + ((b.calories - a.calories) * fraction)
    }

    private func activityStartTimestamp(
        records: [RawFITRecord],
        timerStartTimestamps: [UInt32],
        sessionStartTimestamps: [UInt32]
    ) -> UInt32? {
        guard let firstRecordTimestamp = records.compactMap(\.timestamp).min() else { return nil }
        return (timerStartTimestamps + sessionStartTimestamps)
            .filter { $0 <= firstRecordTimestamp }
            .min()
    }

    private func cadenceStepsPerMinute(_ record: RawFITRecord) -> Int? {
        guard let cadence = record.cadence else { return nil }
        return Int(((Double(cadence) + (record.fractionalCadence ?? 0)) * 2).rounded())
    }

    private func syntheticStartDistance(_ record: RawFITRecord, elapsed: TimeInterval) -> Double? {
        guard let distance = record.distanceMeters, elapsed > 0 else { return record.distanceMeters }
        let startupSpeed = distance / elapsed
        return startupSpeed <= maximumPlausibleStartupSpeedMetersPerSecond ? 0 : distance
    }

    private func compressedSpeedDistance(
        bytes: [UInt8],
        accumulator: inout CompressedDistanceAccumulator
    ) -> (speedMetersPerSecond: Double, distanceMeters: Double)? {
        guard bytes.count >= 3 else { return nil }
        let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16)
        let speedRaw = UInt16(raw & 0x0FFF)
        let distanceRaw = UInt16((raw >> 12) & 0x0FFF)
        guard speedRaw != 0x0FFF, distanceRaw != 0x0FFF else { return nil }
        return (
            speedMetersPerSecond: Double(speedRaw) / 100,
            distanceMeters: accumulator.meters(for: distanceRaw)
        )
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
            || stepLengthMeters != nil
            || temperatureCelsius != nil
    }
}
