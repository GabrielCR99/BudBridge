/// QCY GATT framing.
///
/// Every write to `1001` and every notification/read of `1002` is one frame:
///
///     FF <len> { <cmd> <n> <payload: n bytes> }*
///
/// `len` counts the bytes after itself. A frame may carry several records
/// (the full-settings read of `1002` returns ~12 of them at once).
public struct Record: Sendable, Hashable, CustomStringConvertible {
    public var command: UInt8
    public var payload: [UInt8]

    public init(_ command: UInt8, _ payload: [UInt8] = []) {
        self.command = command
        self.payload = payload
    }

    public init(_ command: CommandID, _ payload: [UInt8] = []) {
        self.init(command.rawValue, payload)
    }

    public var id: CommandID? { CommandID(rawValue: command) }

    public var description: String {
        let name = id.map { "\($0)" } ?? String(format: "0x%02X", command)
        return "\(name)[\(payload.hex)]"
    }
}

public enum FrameError: Error, Sendable, Equatable {
    case tooShort
    case badStartByte(UInt8)
    case lengthMismatch(declared: Int, actual: Int)
    case truncatedRecord(offset: Int)
    case payloadTooLarge
}

public enum Frame {
    public static let startByte: UInt8 = 0xFF

    public static func encode(_ records: Record...) -> [UInt8] {
        encode(records)
    }

    public static func encode(_ records: [Record]) -> [UInt8] {
        var body: [UInt8] = []
        for record in records {
            precondition(record.payload.count <= 0xFF, "record payload exceeds one length byte")
            body.append(record.command)
            body.append(UInt8(record.payload.count))
            body.append(contentsOf: record.payload)
        }
        precondition(body.count <= 0xFF, "frame body exceeds one length byte")
        return [startByte, UInt8(body.count)] + body
    }

    public static func decode(_ bytes: some Collection<UInt8>) throws(FrameError) -> [Record] {
        let bytes = Array(bytes)
        guard bytes.count >= 2 else { throw .tooShort }
        guard bytes[0] == startByte else { throw .badStartByte(bytes[0]) }
        let declared = Int(bytes[1])
        guard declared == bytes.count - 2 else {
            throw .lengthMismatch(declared: declared, actual: bytes.count - 2)
        }

        var records: [Record] = []
        var index = 2
        while index < bytes.count {
            guard index + 1 < bytes.count else { throw .truncatedRecord(offset: index) }
            let command = bytes[index]
            let length = Int(bytes[index + 1])
            let start = index + 2
            guard start + length <= bytes.count else { throw .truncatedRecord(offset: index) }
            records.append(Record(command, Array(bytes[start..<start + length])))
            index = start + length
        }
        return records
    }
}

extension Collection<UInt8> {
    public var hex: String {
        map { byte in
            let digits = Array("0123456789ABCDEF")
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }.joined()
    }
}

extension Array<UInt8> {
    /// Parses a hex string such as `"FF03230101"`; returns `nil` on odd length or invalid digits.
    public init?(hex: String) {
        let chars = [Character](hex.filter { !$0.isWhitespace })
        guard chars.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String([chars[i], chars[i + 1]]), radix: 16) else { return nil }
            result.append(byte)
        }
        self = result
    }
}
