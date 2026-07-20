import Foundation

public enum GPXError: Error, CustomStringConvertible, LocalizedError {
    case unreadable(String)
    case fileTooLarge(maximumBytes: Int, actualBytes: Int)
    case malformedXML(String)
    case noTrackPoints

    public var description: String {
        switch self {
        case let .unreadable(message):
            return "GPX file could not be read: \(message)."
        case let .fileTooLarge(maximumBytes, actualBytes):
            return "GPX file is too large. Maximum is \(maximumBytes) bytes, found \(actualBytes)."
        case let .malformedXML(message):
            return "GPX XML is malformed: \(message)."
        case .noTrackPoints:
            return "GPX file contains no usable track points."
        }
    }

    public var errorDescription: String? {
        description
    }
}

public final class GPXParser {
    static let maximumFileSizeBytes = 64 * 1024 * 1024

    public init() {}

    public func parse(url: URL) throws -> TelemetrySeries {
        do {
            return try parseActivity(url: url).series
        } catch let error as GPXError {
            throw error
        } catch {
            throw GPXError.unreadable(error.localizedDescription)
        }
    }

    public func parseActivity(url: URL) throws -> ParsedActivity {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > Self.maximumFileSizeBytes {
                throw GPXError.fileTooLarge(maximumBytes: Self.maximumFileSizeBytes, actualBytes: fileSize)
            }
            return try parseActivity(data: Data(contentsOf: url))
        } catch let error as GPXError {
            throw error
        } catch {
            throw GPXError.unreadable(error.localizedDescription)
        }
    }

    public func parse(data: Data) throws -> TelemetrySeries {
        try parseActivity(data: data).series
    }

    public func parseActivity(data: Data) throws -> ParsedActivity {
        guard data.count <= Self.maximumFileSizeBytes else {
            throw GPXError.fileTooLarge(maximumBytes: Self.maximumFileSizeBytes, actualBytes: data.count)
        }
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate

        guard parser.parse() else {
            if let error = parser.parserError {
                throw GPXError.malformedXML(error.localizedDescription)
            }
            throw GPXError.malformedXML("Unknown parser error")
        }

        if let error = delegate.error {
            throw error
        }

        guard !delegate.points.isEmpty else {
            throw GPXError.noTrackPoints
        }

        let sport = delegate.trackTypeText.flatMap { TelemetrySport(gpxTypeText: $0) }
        let series = TelemetrySeries(samples: samples(from: delegate.points, sport: sport))
        return ParsedActivity(series: series, sport: sport)
    }

    private func samples(from points: [RawGPXTrackPoint], sport: TelemetrySport?) -> [TelemetrySample] {
        let elapsedValues = monotonicElapsedValues(for: points)
        return points.enumerated().map { index, point in
            return TelemetrySample(
                elapsed: elapsedValues[index],
                date: point.date,
                latitude: point.latitude,
                longitude: point.longitude,
                altitudeMeters: point.altitudeMeters,
                heartRate: point.heartRate,
                cadence: point.cadence.flatMap { Self.cadenceValue($0, sport: sport) },
                distanceMeters: point.distanceMeters,
                speedMetersPerSecond: point.speedMetersPerSecond,
                powerWatts: point.powerWatts,
                totalCalories: point.totalCalories,
                stepLengthMeters: point.stepLengthMeters,
                temperatureCelsius: point.temperatureCelsius,
                trackSegmentIndex: point.trackSegmentIndex
            )
        }
    }

    private func monotonicElapsedValues(for points: [RawGPXTrackPoint]) -> [TimeInterval] {
        guard let firstDatedIndex = points.firstIndex(where: { $0.date != nil }),
              let firstDate = points[firstDatedIndex].date else {
            return points.indices.map(TimeInterval.init)
        }

        var previous: TimeInterval?
        return points.enumerated().map { index, point in
            let candidate = point.date.map {
                $0.timeIntervalSince(firstDate) + TimeInterval(firstDatedIndex)
            } ?? ((previous ?? -1) + 1)
            let elapsed: TimeInterval
            if let previous, candidate <= previous {
                elapsed = previous + 1
            } else {
                elapsed = max(0, candidate)
            }
            previous = elapsed
            return elapsed
        }
    }

    private static func cadenceValue(_ rawCadence: Int, sport: TelemetrySport?) -> Int? {
        guard rawCadence >= 0 else { return nil }
        if sport == .cycling {
            return rawCadence
        }
        return rawCadence < 130 ? rawCadence * 2 : rawCadence
    }
}

private struct RawGPXTrackPoint {
    var trackSegmentIndex: Int?
    var latitude: Double?
    var longitude: Double?
    var altitudeMeters: Double?
    var date: Date?
    var heartRate: Int?
    var cadence: Int?
    var distanceMeters: Double?
    var speedMetersPerSecond: Double?
    var powerWatts: Int?
    var totalCalories: Double?
    var stepLengthMeters: Double?
    var temperatureCelsius: Int?

    var hasUsablePayload: Bool {
        latitude != nil
            || longitude != nil
            || altitudeMeters != nil
            || date != nil
            || heartRate != nil
            || cadence != nil
            || distanceMeters != nil
            || speedMetersPerSecond != nil
            || powerWatts != nil
            || totalCalories != nil
            || stepLengthMeters != nil
            || temperatureCelsius != nil
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var points: [RawGPXTrackPoint] = []
    var trackTypeText: String?
    var error: GPXError?

    private var currentPoint: RawGPXTrackPoint?
    private var currentTrackSegmentIndex: Int?
    private var nextTrackSegmentIndex = 0
    private var currentElement: String?
    private var textBuffer = ""
    private var isCapturingTrackType = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedElementName(elementName)
        if name == "trkseg" {
            currentTrackSegmentIndex = nextTrackSegmentIndex
            nextTrackSegmentIndex += 1
        }
        if name == "trkpt" {
            currentPoint = RawGPXTrackPoint(
                trackSegmentIndex: currentTrackSegmentIndex,
                latitude: double(attributeDict["lat"]),
                longitude: double(attributeDict["lon"])
            )
        }

        if currentPoint == nil, name == "type", trackTypeText == nil {
            isCapturingTrackType = true
            textBuffer = ""
            return
        }

        guard currentPoint != nil else { return }
        currentElement = name
        textBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingTrackType || (currentPoint != nil && currentElement != nil) else { return }
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalizedElementName(elementName)
        if name == "trkseg" {
            currentTrackSegmentIndex = nil
        }
        if isCapturingTrackType, name == "type" {
            let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            trackTypeText = text.isEmpty ? nil : text
            isCapturingTrackType = false
            textBuffer = ""
            return
        }
        guard currentPoint != nil else { return }

        if name == "trkpt" {
            if let point = currentPoint, point.hasUsablePayload {
                points.append(point)
            }
            currentPoint = nil
            currentElement = nil
            textBuffer = ""
            return
        }

        guard let element = currentElement, element == name else { return }
        apply(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines), to: name)
        currentElement = nil
        textBuffer = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = .malformedXML(parseError.localizedDescription)
    }

    private func apply(_ value: String, to elementName: String) {
        guard !value.isEmpty else { return }

        switch elementName {
        case "ele":
            currentPoint?.altitudeMeters = double(value)
        case "time":
            currentPoint?.date = date(value)
        case "hr", "heartrate", "heart_rate":
            currentPoint?.heartRate = integer(value)
        case "cad", "cadence":
            currentPoint?.cadence = integer(value)
        case "distance", "dist":
            currentPoint?.distanceMeters = double(value)
        case "speed":
            currentPoint?.speedMetersPerSecond = double(value)
        case "power", "watts":
            currentPoint?.powerWatts = integer(value)
        case "calories", "calorie":
            currentPoint?.totalCalories = double(value)
        case "steplength", "step_length":
            currentPoint?.stepLengthMeters = double(value)
        case "atemp", "temp", "temperature":
            currentPoint?.temperatureCelsius = integer(value)
        default:
            return
        }
    }

    private func normalizedElementName(_ elementName: String) -> String {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        return localName
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    private func date(_ value: String) -> Date? {
        Self.fractionalDateFormatter.date(from: value) ?? Self.internetDateFormatter.date(from: value)
    }

    private func double(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed), parsed.isFinite else { return nil }
        return parsed
    }

    private func integer(_ value: String?) -> Int? {
        guard let parsed = double(value) else { return nil }
        return Int(exactly: parsed.rounded())
    }
}
