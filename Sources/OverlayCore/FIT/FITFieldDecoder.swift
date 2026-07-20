import Foundation

enum FITFieldDecoder {
    static func string(bytes: [UInt8]) -> String? {
        let trimmed = bytes.prefix { $0 != 0 }
        guard !trimmed.isEmpty else { return nil }
        return String(bytes: trimmed, encoding: .utf8)
    }

    static func number(bytes: [UInt8], baseType: UInt8, endian: FITEndian) -> Double? {
        let baseNumber = baseType & 0x1F
        let width = byteWidth(forBaseNumber: baseNumber)
        guard width > 0, bytes.count >= width else { return nil }

        let raw = unsignedInteger(bytes: Array(bytes[0..<width]), endian: endian)
        if isInvalid(raw: raw, baseNumber: baseNumber, width: width) {
            return nil
        }

        let value: Double
        switch baseNumber {
        case 1:
            value = Double(Int8(bitPattern: UInt8(raw & 0xFF)))
        case 3:
            value = Double(Int16(bitPattern: UInt16(raw & 0xFFFF)))
        case 5:
            value = Double(Int32(bitPattern: UInt32(raw & 0xFFFF_FFFF)))
        case 8:
            value = Double(Float(bitPattern: UInt32(raw & 0xFFFF_FFFF)))
        case 9:
            value = Double(bitPattern: raw)
        case 14:
            value = Double(Int64(bitPattern: raw))
        default:
            value = Double(raw)
        }
        return value.isFinite ? value : nil
    }

    private static func byteWidth(forBaseNumber baseNumber: UInt8) -> Int {
        switch baseNumber {
        case 0, 1, 2, 10, 13:
            return 1
        case 3, 4, 11:
            return 2
        case 5, 6, 8, 12:
            return 4
        case 9, 14, 15, 16:
            return 8
        default:
            return 0
        }
    }

    private static func unsignedInteger(bytes: [UInt8], endian: FITEndian) -> UInt64 {
        var value: UInt64 = 0
        switch endian {
        case .little:
            for (index, byte) in bytes.enumerated() {
                value |= UInt64(byte) << UInt64(index * 8)
            }
        case .big:
            for byte in bytes {
                value = (value << 8) | UInt64(byte)
            }
        }
        return value
    }

    private static func isInvalid(raw: UInt64, baseNumber: UInt8, width: Int) -> Bool {
        switch baseNumber {
        case 0, 2:
            return raw == 0xFF
        case 1:
            return raw == 0x7F
        case 3:
            return raw == 0x7FFF
        case 4:
            return raw == 0xFFFF
        case 5:
            return raw == 0x7FFF_FFFF
        case 6:
            return raw == 0xFFFF_FFFF
        case 10, 11, 12, 16:
            return raw == 0
        case 15:
            return raw == UInt64.max
        case 14:
            return raw == 0x7FFF_FFFF_FFFF_FFFF
        case 8:
            return raw == 0xFFFF_FFFF
        case 9:
            return raw == 0xFFFF_FFFF_FFFF_FFFF
        case 13:
            return raw == 0xFF
        default:
            return raw == (width >= 8 ? UInt64.max : ((UInt64(1) << UInt64(width * 8)) - 1))
        }
    }
}
