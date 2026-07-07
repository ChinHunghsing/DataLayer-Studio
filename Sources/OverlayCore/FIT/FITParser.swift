import Foundation

struct FITFieldDefinition {
    var number: UInt8
    var size: UInt8
    var baseType: UInt8
}

struct FITDeveloperFieldDefinition {
    var number: UInt8
    var size: UInt8
    var developerDataIndex: UInt8
}

struct FITLocalMessageDefinition {
    var endian: FITEndian
    var globalMessageNumber: UInt16
    var fields: [FITFieldDefinition]
    var developerFields: [FITDeveloperFieldDefinition]
}

struct FITDeveloperFieldKey: Hashable {
    var developerDataIndex: UInt8
    var fieldDefinitionNumber: UInt8
}

struct FITDeveloperFieldDescription {
    var developerDataIndex: UInt8?
    var fieldDefinitionNumber: UInt8?
    var fitBaseTypeID: UInt8?
    var fieldName: String?
    var units: String?
    var scale: Double?
    var offset: Double?

    var key: FITDeveloperFieldKey? {
        guard let developerDataIndex, let fieldDefinitionNumber else { return nil }
        return FITDeveloperFieldKey(
            developerDataIndex: developerDataIndex,
            fieldDefinitionNumber: fieldDefinitionNumber
        )
    }

    var normalizedFieldName: String {
        (fieldName ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func scaledValue(_ value: Double) -> Double {
        (value - (offset ?? 0)) / max(scale ?? 1, 0.000_001)
    }
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
    var verticalOscillationCentimeters: Double?
    var groundContactTimeMilliseconds: Double?
    var groundContactTimePercent: Double?
    var groundContactTimeBalancePercent: Double?
    var verticalRatioPercent: Double?
    var respirationRateBreathsPerMinute: Double?
    var stepSpeedLossPercent: Double?
    var formPowerWatts: Int?
    var airPowerWatts: Int?
    var legSpringStiffnessKilonewtonsPerMeter: Double?
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

    var isTimerStop: Bool {
        event == 0 && (eventType == 1 || eventType == 4)
    }
}

struct RawFITSession {
    var timestamp: UInt32?
    var startTime: UInt32?
    var totalElapsedTimeSeconds: TimeInterval?
    var totalTimerTimeSeconds: TimeInterval?
    var totalDistanceMeters: Double?
    var totalCalories: Int?
}

struct RawFITLap {
    var timestamp: UInt32?
    var startTime: UInt32?
    var totalElapsedTimeSeconds: TimeInterval?
    var totalTimerTimeSeconds: TimeInterval?
    var totalDistanceMeters: Double?
    var totalCalories: Int?
}

struct ParsedFITMessage {
    var timestamp: UInt32?
    var record: RawFITRecord?
    var event: RawFITEvent?
    var session: RawFITSession?
    var lap: RawFITLap?
    var developerFieldDescription: FITDeveloperFieldDescription?
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
    private let lapAnchorDistanceToleranceMeters = 25.0
    private let minimumFinalSampleSpeedWindowSeconds: TimeInterval = 1

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
        var timerEvents: [RawFITEvent] = []
        var timerStartTimestamps: [UInt32] = []
        var sessionStartTimestamps: [UInt32] = []
        var compressedDistanceAccumulator = CompressedDistanceAccumulator()
        var developerFieldDescriptions: [FITDeveloperFieldKey: FITDeveloperFieldDescription] = [:]
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
                    compressedDistanceAccumulator: &compressedDistanceAccumulator,
                    developerFieldDescriptions: developerFieldDescriptions
                )
                if let timestamp = parsed.timestamp {
                    lastTimestamp = timestamp
                }
                if let description = parsed.developerFieldDescription,
                   let key = description.key {
                    developerFieldDescriptions[key] = description
                }
                append(
                    parsed: parsed,
                    definition: definition,
                    records: &records,
                    laps: &laps,
                    sessions: &sessions,
                    timerEvents: &timerEvents,
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
                        compressedDistanceAccumulator: &compressedDistanceAccumulator,
                        developerFieldDescriptions: developerFieldDescriptions
                    )
                    if let timestamp = parsed.timestamp {
                        lastTimestamp = timestamp
                    }
                    if let description = parsed.developerFieldDescription,
                       let key = description.key {
                        developerFieldDescriptions[key] = description
                    }
                    append(
                        parsed: parsed,
                        definition: definition,
                        records: &records,
                        laps: &laps,
                        sessions: &sessions,
                        timerEvents: &timerEvents,
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
        let parsedSamples = samples(
            from: records,
            activityStartTimestamp: activityStartTimestamp,
            timerEvents: timerEvents,
            caloriePoints: caloriePoints(
                laps: laps,
                sessions: sessions,
                records: records,
                activityStartTimestamp: activityStartTimestamp,
                timerEvents: timerEvents
            )
        )
        var series = TelemetrySeries(samples: parsedSamples)
        let lapAnchorSamples = authoritativeLapSamples(
            laps: laps,
            sessions: sessions,
            currentSeries: series,
            activityStartTimestamp: activityStartTimestamp ?? records.compactMap(\.timestamp).min(),
            timerEvents: timerEvents
        )
        if !lapAnchorSamples.isEmpty {
            series = TelemetrySeries(samples: series.samples + lapAnchorSamples)
        }
        if let correctedFinalSample = authoritativeFinalSample(
            sessions: sessions,
            currentSeries: series,
            activityStartTimestamp: activityStartTimestamp,
            timerEvents: timerEvents
        ) {
            return TelemetrySeries(samples: series.samples + [correctedFinalSample])
        }
        return series
    }

    private func append(
        parsed: ParsedFITMessage,
        definition: FITLocalMessageDefinition,
        records: inout [RawFITRecord],
        laps: inout [RawFITLap],
        sessions: inout [RawFITSession],
        timerEvents: inout [RawFITEvent],
        timerStartTimestamps: inout [UInt32],
        sessionStartTimestamps: inout [UInt32]
    ) {
        switch definition.globalMessageNumber {
        case 20:
            if let record = parsed.record, record.hasTelemetryPayload {
                records.append(record)
            }
        case 21:
            if let event = parsed.event {
                if event.isTimerStart, let timestamp = event.timestamp {
                    timerStartTimestamps.append(timestamp)
                }
                if event.isTimerStart || event.isTimerStop {
                    timerEvents.append(event)
                }
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

        var developerFields: [FITDeveloperFieldDefinition] = []
        if hasDeveloperData {
            let developerFieldCount = Int(try reader.readUInt8())
            developerFields.reserveCapacity(developerFieldCount)
            for _ in 0..<developerFieldCount {
                developerFields.append(FITDeveloperFieldDefinition(
                    number: try reader.readUInt8(),
                    size: try reader.readUInt8(),
                    developerDataIndex: try reader.readUInt8()
                ))
            }
        }

        return FITLocalMessageDefinition(
            endian: endian,
            globalMessageNumber: globalMessageNumber,
            fields: fields,
            developerFields: developerFields
        )
    }

    private func parseDataMessage(
        definition: FITLocalMessageDefinition,
        reader: inout ByteReader,
        compressedTimestamp: UInt32?,
        compressedDistanceAccumulator: inout CompressedDistanceAccumulator,
        developerFieldDescriptions: [FITDeveloperFieldKey: FITDeveloperFieldDescription]
    ) throws -> ParsedFITMessage {
        var timestamp = compressedTimestamp
        var record = RawFITRecord(timestamp: compressedTimestamp)
        var event = RawFITEvent(timestamp: compressedTimestamp)
        var session = RawFITSession(timestamp: compressedTimestamp)
        var lap = RawFITLap(timestamp: compressedTimestamp)
        var developerFieldDescription = FITDeveloperFieldDescription()

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

            if definition.globalMessageNumber == 206 {
                switch field.number {
                case 3:
                    developerFieldDescription.fieldName = FITFieldDecoder.string(bytes: bytes)
                case 8:
                    developerFieldDescription.units = FITFieldDecoder.string(bytes: bytes)
                default:
                    if let value = FITFieldDecoder.number(
                        bytes: bytes,
                        baseType: field.baseType,
                        endian: definition.endian
                    ) {
                        applyFieldDescriptionValue(value, fieldNumber: field.number, to: &developerFieldDescription)
                    }
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
                case 39:
                    record.verticalOscillationCentimeters = value / 100
                case 40:
                    record.groundContactTimePercent = value / 100
                case 41:
                    record.groundContactTimeMilliseconds = value / 10
                case 13:
                    record.temperatureCelsius = Int(value)
                case 53:
                    record.fractionalCadence = value / 128
                case 73:
                    record.speedMetersPerSecond = value / 1000
                case 78:
                    record.altitudeMeters = (value / 5) - 500
                case 83:
                    record.verticalRatioPercent = value / 100
                case 84:
                    record.groundContactTimeBalancePercent = value / 100
                case 85:
                    record.stepLengthMeters = value / 10_000
                case 108:
                    record.respirationRateBreathsPerMinute = value / 100
                case 147:
                    record.stepSpeedLossPercent = value / 100
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
                case 7:
                    session.totalElapsedTimeSeconds = value / 1000
                case 8:
                    session.totalTimerTimeSeconds = value / 1000
                case 9:
                    session.totalDistanceMeters = value / 100
                case 11:
                    session.totalCalories = Int(value)
                default:
                    continue
                }
            case 19:
                switch field.number {
                case 2:
                    lap.startTime = UInt32(value)
                case 7:
                    lap.totalElapsedTimeSeconds = value / 1000
                case 8:
                    lap.totalTimerTimeSeconds = value / 1000
                case 9:
                    lap.totalDistanceMeters = value / 100
                case 11:
                    lap.totalCalories = Int(value)
                default:
                    continue
                }
            default:
                continue
            }
        }

        for developerField in definition.developerFields {
            let bytes = try reader.readBytes(count: Int(developerField.size))
            guard definition.globalMessageNumber == 20 else { continue }
            let key = FITDeveloperFieldKey(
                developerDataIndex: developerField.developerDataIndex,
                fieldDefinitionNumber: developerField.number
            )
            guard let description = developerFieldDescriptions[key],
                  let baseType = description.fitBaseTypeID,
                  let value = FITFieldDecoder.number(
                    bytes: bytes,
                    baseType: baseType,
                    endian: definition.endian
                  ) else {
                continue
            }
            applyDeveloperRecordValue(description.scaledValue(value), description: description, to: &record)
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
            lap: definition.globalMessageNumber == 19 ? lap : nil,
            developerFieldDescription: definition.globalMessageNumber == 206 ? developerFieldDescription : nil
        )
    }

    private func applyFieldDescriptionValue(
        _ value: Double,
        fieldNumber: UInt8,
        to description: inout FITDeveloperFieldDescription
    ) {
        switch fieldNumber {
        case 0:
            description.developerDataIndex = UInt8(value)
        case 1:
            description.fieldDefinitionNumber = UInt8(value)
        case 2:
            description.fitBaseTypeID = UInt8(value)
        case 6:
            description.scale = value
        case 7:
            description.offset = value
        default:
            return
        }
    }

    private func applyDeveloperRecordValue(
        _ value: Double,
        description: FITDeveloperFieldDescription,
        to record: inout RawFITRecord
    ) {
        switch description.normalizedFieldName {
        case "airpower":
            record.airPowerWatts = Int(value.rounded())
        case "formpower":
            record.formPowerWatts = Int(value.rounded())
        case "legspringstiffness":
            record.legSpringStiffnessKilonewtonsPerMeter = value
        default:
            return
        }
    }

    private func samples(
        from records: [RawFITRecord],
        activityStartTimestamp: UInt32?,
        timerEvents: [RawFITEvent],
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
                elapsed = timerElapsed(
                    for: timestamp,
                    activityStartTimestamp: firstTimestamp,
                    timerEvents: timerEvents
                )
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
                verticalOscillationCentimeters: record.verticalOscillationCentimeters,
                groundContactTimeMilliseconds: record.groundContactTimeMilliseconds,
                groundContactTimePercent: record.groundContactTimePercent,
                groundContactTimeBalancePercent: record.groundContactTimeBalancePercent,
                verticalRatioPercent: record.verticalRatioPercent,
                respirationRateBreathsPerMinute: record.respirationRateBreathsPerMinute,
                stepSpeedLossPercent: record.stepSpeedLossPercent,
                formPowerWatts: record.formPowerWatts,
                airPowerWatts: record.airPowerWatts,
                legSpringStiffnessKilonewtonsPerMeter: record.legSpringStiffnessKilonewtonsPerMeter,
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
                verticalOscillationCentimeters: firstRecord.verticalOscillationCentimeters,
                groundContactTimeMilliseconds: firstRecord.groundContactTimeMilliseconds,
                groundContactTimePercent: firstRecord.groundContactTimePercent,
                groundContactTimeBalancePercent: firstRecord.groundContactTimeBalancePercent,
                verticalRatioPercent: firstRecord.verticalRatioPercent,
                respirationRateBreathsPerMinute: firstRecord.respirationRateBreathsPerMinute,
                stepSpeedLossPercent: firstRecord.stepSpeedLossPercent,
                formPowerWatts: firstRecord.formPowerWatts,
                airPowerWatts: firstRecord.airPowerWatts,
                legSpringStiffnessKilonewtonsPerMeter: firstRecord.legSpringStiffnessKilonewtonsPerMeter,
                totalCalories: calories(at: 0, points: caloriePoints),
                stepLengthMeters: firstRecord.stepLengthMeters,
                temperatureCelsius: firstRecord.temperatureCelsius
            ), at: 0)
        }

        return samples
    }

    private func authoritativeFinalSample(
        sessions: [RawFITSession],
        currentSeries: TelemetrySeries,
        activityStartTimestamp: UInt32?,
        timerEvents: [RawFITEvent]
    ) -> TelemetrySample? {
        guard let activityStartTimestamp else { return nil }

        let candidates = sessions.compactMap { session -> (elapsed: TimeInterval, distance: Double, timestamp: UInt32?)? in
            guard let elapsed = sessionEndElapsed(
                session,
                activityStartTimestamp: activityStartTimestamp,
                timerEvents: timerEvents
            ),
                  elapsed.isFinite,
                  let distance = session.totalDistanceMeters,
                  distance.isFinite,
                  distance >= 0 else {
                return nil
            }
            return (elapsed, distance, session.timestamp)
        }
        guard let authoritative = candidates.max(by: { $0.elapsed < $1.elapsed }) else {
            return nil
        }

        let currentDuration = currentSeries.duration
        let currentDistance = currentSeries.sample(at: currentDuration).distanceMeters
        let needsDurationCorrection = authoritative.elapsed > currentDuration + 0.000_5
        let needsDistanceCorrection = authoritative.distance > (currentDistance ?? 0) + 0.01
        guard needsDurationCorrection || needsDistanceCorrection else {
            return nil
        }

        var finalSample = currentSeries.sample(at: currentDuration)
        finalSample.elapsed = max(authoritative.elapsed, currentDuration)
        finalSample.distanceMeters = max(authoritative.distance, currentDistance ?? 0)

        if let date = currentSeries.date(atElapsed: finalSample.elapsed) {
            finalSample.date = date
        } else if let timestamp = authoritative.timestamp {
            let fitEpoch = Date(timeIntervalSince1970: 631_065_600)
            finalSample.date = fitEpoch.addingTimeInterval(TimeInterval(timestamp))
        }

        if let currentDistance,
           finalSample.elapsed > currentDuration,
           finalSample.distanceMeters ?? 0 >= currentDistance {
            let deltaTime = finalSample.elapsed - currentDuration
            let speed = ((finalSample.distanceMeters ?? currentDistance) - currentDistance) / deltaTime
            // 时间窗过短或速度不合理时保留继承的末样本速度，避免末帧配速尖峰或归零
            if deltaTime >= minimumFinalSampleSpeedWindowSeconds,
               speed.isFinite,
               speed >= 0,
               speed <= maximumPlausibleStartupSpeedMetersPerSecond {
                finalSample.speedMetersPerSecond = speed
            }
        }

        return finalSample
    }

    private func authoritativeLapSamples(
        laps: [RawFITLap],
        sessions: [RawFITSession],
        currentSeries: TelemetrySeries,
        activityStartTimestamp: UInt32?,
        timerEvents: [RawFITEvent]
    ) -> [TelemetrySample] {
        guard let activityStartTimestamp else { return [] }

        let sessionEnd = sessions.compactMap {
            sessionEndElapsed($0, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents)
        }.max()
        let sessionDistance = sessions.compactMap(\.totalDistanceMeters).filter(\.isFinite).max()
        let sortedLaps = laps.sorted {
            ($0.startTime ?? $0.timestamp ?? 0) < ($1.startTime ?? $1.timestamp ?? 0)
        }

        var cumulativeDistance = 0.0
        var previousAnchorDistance = 0.0
        var anchors: [TelemetrySample] = []

        for lap in sortedLaps {
            guard let lapDistance = lap.totalDistanceMeters,
                  lapDistance.isFinite,
                  lapDistance > 0,
                  let duration = lap.totalTimerTimeSeconds ?? lap.totalElapsedTimeSeconds,
                  duration.isFinite,
                  duration > 0 else {
                continue
            }
            cumulativeDistance += lapDistance
            // 分段累计和可能超出会话实测总里程，超出的锚点会凭空抬高距离，跳过
            if let sessionDistance, cumulativeDistance > sessionDistance + 0.01 {
                continue
            }

            let startElapsed: TimeInterval
            if let startTime = lap.startTime {
                startElapsed = timerElapsed(
                    for: startTime,
                    activityStartTimestamp: activityStartTimestamp,
                    timerEvents: timerEvents
                )
            } else if let timestamp = lap.timestamp {
                startElapsed = timerElapsed(
                    for: timestamp,
                    activityStartTimestamp: activityStartTimestamp,
                    timerEvents: timerEvents
                ) - duration
            } else {
                continue
            }

            var anchorElapsed = startElapsed + duration
            // 记录距离已在结束时间戳处精确到达分段累计值时，锚点直接落在该时刻，
            // 避免 start+duration 略早于记录时间线时把补账距离挤进极短时间造成段速尖峰；
            // 记录仍落后于分段累计的场合保持 start+duration，让锚点继续修正记录滞后
            if let timestamp = lap.timestamp {
                let timestampElapsed = timerElapsed(
                    for: timestamp,
                    activityStartTimestamp: activityStartTimestamp,
                    timerEvents: timerEvents
                )
                if timestampElapsed.isFinite,
                   timestampElapsed > 0,
                   abs(timestampElapsed - anchorElapsed) > 0.000_5,
                   let candidateDistance = currentSeries.sample(at: timestampElapsed).distanceMeters,
                   abs(candidateDistance - cumulativeDistance) <= 0.01 {
                    anchorElapsed = timestampElapsed
                }
            }
            guard anchorElapsed.isFinite,
                  anchorElapsed > 0,
                  cumulativeDistance > previousAnchorDistance + 0.001 else {
                continue
            }
            if let sessionEnd, anchorElapsed > sessionEnd + 0.001 {
                continue
            }

            var anchor = currentSeries.sample(at: anchorElapsed)
            guard let currentDistance = anchor.distanceMeters,
                  abs(currentDistance - cumulativeDistance) <= lapAnchorDistanceToleranceMeters else {
                continue
            }

            anchor.elapsed = anchorElapsed
            anchor.distanceMeters = cumulativeDistance
            if let date = currentSeries.date(atElapsed: anchorElapsed) {
                anchor.date = date
            }
            anchors.append(anchor)
            previousAnchorDistance = cumulativeDistance
        }

        return anchors
    }

    private func caloriePoints(
        laps: [RawFITLap],
        sessions: [RawFITSession],
        records: [RawFITRecord],
        activityStartTimestamp: UInt32?,
        timerEvents: [RawFITEvent]
    ) -> [CaloriePoint] {
        guard let activityStartTimestamp = activityStartTimestamp ?? records.compactMap(\.timestamp).min() else {
            return []
        }
        var points = [CaloriePoint(elapsed: 0, calories: 0)]
        var cumulativeCalories = 0.0

        for lap in laps.sorted(by: { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }) {
            guard let elapsed = lapEndElapsed(lap, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents),
                  let lapCalories = lap.totalCalories,
                  lapCalories >= 0 else {
                continue
            }

            cumulativeCalories += Double(lapCalories)
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

        let sessionEnd = sessions.compactMap {
            sessionEndElapsed($0, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents)
        }.max()
        let recordEndElapsed = records
            .compactMap(\.timestamp)
            .max()
            .map { timerElapsed(for: $0, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents) }
        guard let endElapsed = sessionEnd ?? recordEndElapsed,
              endElapsed > 0 else {
            return []
        }

        return [
            CaloriePoint(elapsed: 0, calories: 0),
            CaloriePoint(
                elapsed: endElapsed,
                calories: Double(totalCalories)
            )
        ]
    }

    private func lapEndElapsed(_ lap: RawFITLap, activityStartTimestamp: UInt32, timerEvents: [RawFITEvent]) -> TimeInterval? {
        if let startTime = lap.startTime,
           let duration = lap.totalTimerTimeSeconds ?? lap.totalElapsedTimeSeconds {
            return timerElapsed(for: startTime, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents) + duration
        }
        guard let timestamp = lap.timestamp, timestamp >= activityStartTimestamp else {
            return nil
        }
        return timerElapsed(for: timestamp, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents)
    }

    private func sessionEndElapsed(_ session: RawFITSession, activityStartTimestamp: UInt32, timerEvents: [RawFITEvent]) -> TimeInterval? {
        if let startTime = session.startTime,
           let duration = session.totalTimerTimeSeconds ?? session.totalElapsedTimeSeconds {
            return timerElapsed(for: startTime, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents) + duration
        }
        guard let timestamp = session.timestamp, timestamp > activityStartTimestamp else {
            return nil
        }
        return timerElapsed(for: timestamp, activityStartTimestamp: activityStartTimestamp, timerEvents: timerEvents)
    }

    private func timerElapsed(
        for timestamp: UInt32,
        activityStartTimestamp: UInt32,
        timerEvents: [RawFITEvent]
    ) -> TimeInterval {
        let wallElapsed = max(0, TimeInterval(Int64(timestamp) - Int64(activityStartTimestamp)))
        let events = timerEvents
            .filter { ($0.isTimerStart || $0.isTimerStop) && $0.timestamp != nil }
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.isTimerStart && !$1.isTimerStart
                }
                return ($0.timestamp ?? 0) < ($1.timestamp ?? 0)
            }
        guard events.contains(where: { $0.isTimerStart }) else { return wallElapsed }

        var activeElapsed: TimeInterval = 0
        var runningSince: UInt32?

        for event in events {
            guard let eventTimestamp = event.timestamp else { continue }
            let eventTime = max(eventTimestamp, activityStartTimestamp)
            guard eventTime <= timestamp else { break }

            if event.isTimerStart {
                runningSince = runningSince ?? eventTime
            } else if event.isTimerStop, let start = runningSince {
                activeElapsed += max(0, TimeInterval(Int64(eventTime) - Int64(start)))
                runningSince = nil
            }
        }

        if let start = runningSince {
            activeElapsed += max(0, TimeInterval(Int64(timestamp) - Int64(start)))
        }
        return activeElapsed
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
            || verticalOscillationCentimeters != nil
            || groundContactTimeMilliseconds != nil
            || groundContactTimePercent != nil
            || groundContactTimeBalancePercent != nil
            || verticalRatioPercent != nil
            || respirationRateBreathsPerMinute != nil
            || stepSpeedLossPercent != nil
            || formPowerWatts != nil
            || airPowerWatts != nil
            || legSpringStiffnessKilonewtonsPerMeter != nil
            || stepLengthMeters != nil
            || temperatureCelsius != nil
    }
}
