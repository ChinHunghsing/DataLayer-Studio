import Foundation

enum FITEndian {
    case little
    case big
}

struct ByteReader {
    let data: Data
    let endOffset: Int
    var offset: Int

    init(data: Data, offset: Int = 0, endOffset: Int? = nil) {
        self.data = data
        self.offset = offset
        self.endOffset = endOffset ?? data.count
    }

    var isAtEnd: Bool {
        offset >= endOffset
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= endOffset else { throw FITError.malformedRecord(offset: offset) }
        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readUInt16(endian: FITEndian) throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        switch endian {
        case .little:
            return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        case .big:
            return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        }
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= endOffset else {
            throw FITError.malformedRecord(offset: offset)
        }
        let bytes = Array(data[offset..<(offset + count)])
        offset += count
        return bytes
    }

    mutating func skip(count: Int) throws {
        guard count >= 0, offset + count <= endOffset else {
            throw FITError.malformedRecord(offset: offset)
        }
        offset += count
    }
}

extension Data {
    func uint16(at offset: Int, endian: FITEndian) -> UInt16 {
        switch endian {
        case .little:
            return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
        case .big:
            return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
        }
    }

    func uint32(at offset: Int, endian: FITEndian) -> UInt32 {
        switch endian {
        case .little:
            return UInt32(self[offset])
                | (UInt32(self[offset + 1]) << 8)
                | (UInt32(self[offset + 2]) << 16)
                | (UInt32(self[offset + 3]) << 24)
        case .big:
            return (UInt32(self[offset]) << 24)
                | (UInt32(self[offset + 1]) << 16)
                | (UInt32(self[offset + 2]) << 8)
                | UInt32(self[offset + 3])
        }
    }
}

