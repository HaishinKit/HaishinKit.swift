import Foundation

/// Small ZIP store writer: packages contain already-compressed MP4 and short raw references.
enum TVQualityZIP {
    nonisolated static func write(names: [String], directory: URL, output: URL) throws {
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        var central = Data()
        for name in names {
            try Task.checkCancellation()
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            let filename = Data(name.utf8)
            let offset = try handle.offset()
            guard data.count < Int(UInt32.max), offset < UInt32.max else { throw QualityError("Package exceeds ZIP limits.") }
            let crc = checksum(data)
            var header = Data()
            header.u32(0x0403_4b50)
            header.u16(20)
            header.u16(0)
            header.u16(0)
            header.u16(0)
            header.u16(0)
            header.u32(crc)
            header.u32(UInt32(data.count))
            header.u32(UInt32(data.count))
            header.u16(UInt16(filename.count))
            header.u16(0)
            header.append(filename)
            try handle.write(contentsOf: header)
            try handle.write(contentsOf: data)
            central.u32(0x0201_4b50)
            central.u16(20)
            central.u16(20)
            central.u16(0)
            central.u16(0)
            central.u16(0)
            central.u16(0)
            central.u32(crc)
            central.u32(UInt32(data.count))
            central.u32(UInt32(data.count))
            central.u16(UInt16(filename.count))
            central.u16(0)
            central.u16(0)
            central.u16(0)
            central.u16(0)
            central.u32(0)
            central.u32(UInt32(offset))
            central.append(filename)
        }
        let offset = try handle.offset()
        try handle.write(contentsOf: central)
        var end = Data()
        end.u32(0x0605_4b50)
        end.u16(0)
        end.u16(0)
        end.u16(UInt16(names.count))
        end.u16(UInt16(names.count))
        end.u32(UInt32(central.count))
        end.u32(UInt32(offset))
        end.u16(0)
        try handle.write(contentsOf: end)
    }
    nonisolated private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb8_8320 : 0) }
        return crc
    }
    nonisolated private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
        return crc ^ 0xffff_ffff
    }
}

extension Data {
    nonisolated fileprivate mutating func u16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    nonisolated fileprivate mutating func u32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
