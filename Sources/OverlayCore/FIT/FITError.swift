import Foundation

public enum FITError: Error, CustomStringConvertible {
    case fileTooSmall
    case fileTooLarge(maximumBytes: Int, actualBytes: Int)
    case unsupportedHeaderSize(Int)
    case invalidSignature
    case truncatedFile(expected: Int, actual: Int)
    case headerCRCMismatch(expected: UInt16, actual: UInt16)
    case fileCRCMismatch(expected: UInt16, actual: UInt16)
    case malformedRecord(offset: Int)
    case missingDefinition(localMessageType: UInt8)
    case noRecordMessages

    public var description: String {
        switch self {
        case .fileTooSmall:
            return "FIT file is too small to contain a valid header."
        case let .fileTooLarge(maximumBytes, actualBytes):
            return "FIT file is too large. Maximum is \(maximumBytes) bytes, found \(actualBytes)."
        case let .unsupportedHeaderSize(size):
            return "Unsupported FIT header size \(size)."
        case .invalidSignature:
            return "FIT header signature is missing .FIT."
        case let .truncatedFile(expected, actual):
            return "FIT file is truncated. Expected at least \(expected) bytes, found \(actual)."
        case let .headerCRCMismatch(expected, actual):
            return "FIT header CRC mismatch. Expected \(expected), found \(actual)."
        case let .fileCRCMismatch(expected, actual):
            return "FIT file CRC mismatch. Expected \(expected), found \(actual)."
        case let .malformedRecord(offset):
            return "Malformed FIT record near byte offset \(offset)."
        case let .missingDefinition(localMessageType):
            return "FIT data message references missing local definition \(localMessageType)."
        case .noRecordMessages:
            return "FIT file contains no standard record messages."
        }
    }
}
