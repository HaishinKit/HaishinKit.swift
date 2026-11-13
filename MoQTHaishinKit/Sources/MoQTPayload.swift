import Foundation

struct MoQTPayload {
    enum Error: Swift.Error {
        case eof
        case invalidField
    }

    private(set) var data: Data
    private(set) var position = 0
    var bytesAvailable: Int { data.count - position }

    init(_ data: Data = Data()) {
        self.data = Data(data)
    }

    mutating func putInt(_ value: UInt64) {
        let bits = UInt64.bitWidth - value.leadingZeroBitCount
        let extra = min(8, max(0, (bits - 1) / 7))
        let prefix = UInt8(truncatingIfNeeded: 0xff << (8 - extra))
        let first = extra == 8 ? 0 : UInt8(truncatingIfNeeded: value >> (8 * extra))
        data.append(prefix | first)
        for index in (0..<extra).reversed() {
            data.append(UInt8(truncatingIfNeeded: value >> (8 * index)))
        }
    }

    mutating func getInt() throws -> UInt64 {
        let first = try getByte()
        let extra = (~first).leadingZeroBitCount
        var value = UInt64(first & (0xff >> extra))
        for _ in 0..<extra {
            value = (value << 8) | UInt64(try getByte())
        }
        return value
    }

    mutating func getByte() throws -> UInt8 {
        guard bytesAvailable > 0 else { throw Error.eof }
        defer { position += 1 }
        return data[position]
    }

    mutating func putByte(_ value: UInt8) {
        data.append(value)
    }

    mutating func putBytes(_ value: Data) {
        putInt(UInt64(value.count))
        putData(value)
    }

    mutating func getBytes(limit: UInt64 = .max) throws -> Data {
        let count = try getInt()
        guard count <= limit else { throw Error.invalidField }
        return try getData(count)
    }

    mutating func putData(_ value: Data) {
        data.append(value)
    }

    mutating func getData(_ count: UInt64) throws -> Data {
        guard count <= UInt64(bytesAvailable) else { throw Error.eof }
        defer { position += Int(count) }
        return data.subdata(in: position..<position + Int(count))
    }

    mutating func remainder() -> Data {
        let result = data.subdata(in: position..<data.count)
        position = data.count
        return result
    }

    mutating func getNamespace() throws -> [Data] {
        let count = try getInt()
        guard count <= 32 else { throw Error.invalidField }
        var remaining: UInt64 = 4096
        return try (0..<count).map { _ in
            let component = try getBytes(limit: remaining)
            guard !component.isEmpty else { throw Error.invalidField }
            remaining -= UInt64(component.count)
            return component
        }
    }

    mutating func putNamespace(_ namespace: [String]) throws {
        guard namespace.count <= 32, namespace.allSatisfy({ !$0.isEmpty }),
              namespace.reduce(0, { $0 + $1.utf8.count }) <= 4096 else { throw Error.invalidField }
        putInt(UInt64(namespace.count))
        for component in namespace {
            putBytes(Data(component.utf8))
        }
    }
}
