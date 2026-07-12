import Foundation

public enum TelemetryFileError: Error, CustomStringConvertible, LocalizedError {
    case unsupportedExtension(String)

    public var description: String {
        switch self {
        case let .unsupportedExtension(fileExtension):
            let suffix = fileExtension.isEmpty ? "missing" : ".\(fileExtension)"
            return "Unsupported activity file extension \(suffix). Use a .fit or .gpx file."
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct TelemetryFileParser {
    private let validateFITCRC: Bool

    public init(validateFITCRC: Bool = true) {
        self.validateFITCRC = validateFITCRC
    }

    public func parse(url: URL) throws -> TelemetrySeries {
        try parseActivity(url: url).series
    }

    public func parseActivity(url: URL) throws -> ParsedActivity {
        switch url.pathExtension.lowercased() {
        case "fit":
            return try FITParser(validateCRC: validateFITCRC).parseActivity(url: url)
        case "gpx":
            return try GPXParser().parseActivity(url: url)
        default:
            throw TelemetryFileError.unsupportedExtension(url.pathExtension.lowercased())
        }
    }
}
