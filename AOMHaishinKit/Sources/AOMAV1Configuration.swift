import Foundation

/// Builds av1C from this encoder's Main-profile, 8-bit I420 sequence header.
enum AOMAV1Configuration {
    static func record(in packet: Data) throws -> Data? {
        let bytes = [UInt8](packet)
        var position = 0
        while position < bytes.count {
            let start = position
            let header = bytes[position]
            position += 1
            guard header & 0x83 == 0x02 else { throw AOMVideoCodecError.unsupportedFormat }
            if header & 4 != 0 {
                guard position < bytes.count else { throw AOMVideoCodecError.unsupportedFormat }
                position += 1
            }
            var size: UInt64 = 0
            var terminated = false
            for index in 0..<8 {
                guard position < bytes.count else { throw AOMVideoCodecError.unsupportedFormat }
                let byte = bytes[position]
                position += 1
                size |= UInt64(byte & 127) << (index * 7)
                if byte & 128 == 0 { terminated = true; break }
            }
            guard terminated, size <= UInt64(bytes.count - position) else { throw AOMVideoCodecError.unsupportedFormat }
            let end = position + Int(size)
            if (header >> 3) & 15 == 1 {
                var bits = Bits(bytes: Array(bytes[position..<end]))
                guard try bits.read(3) == 0 else { throw AOMVideoCodecError.unsupportedFormat }
                _ = try bits.read(1) // still_picture
                let reduced = try bits.read(1) != 0
                let level: Int
                var tier = 0
                if reduced {
                    level = try bits.read(5)
                } else {
                    if try bits.read(1) != 0 { // timing_info_present_flag
                        _ = try bits.read(32)
                        _ = try bits.read(32)
                        if try bits.read(1) != 0 { try bits.skipUVLC() }
                        if try bits.read(1) != 0 {
                            _ = try bits.read(5)
                            _ = try bits.read(32)
                            _ = try bits.read(5)
                            _ = try bits.read(5)
                        }
                    }
                    _ = try bits.read(1) // initial_display_delay_present_flag
                    _ = try bits.read(5) // operating_points_cnt_minus_1
                    _ = try bits.read(12) // operating_point_idc[0]
                    level = try bits.read(5)
                    if level > 7 { tier = try bits.read(1) }
                }
                // The bridge fixes profile 0, 8-bit, non-monochrome I420 with unknown chroma position.
                return Data([0x81, UInt8(level), UInt8(tier << 7) | 0x0C, 0]) + Data(bytes[start..<end])
            }
            position = end
        }
        return nil
    }

    private struct Bits {
        let bytes: [UInt8]
        var position = 0
        mutating func read(_ count: Int) throws -> Int {
            guard count <= bytes.count * 8 - position else { throw AOMVideoCodecError.unsupportedFormat }
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | Int((bytes[position / 8] >> (7 - position % 8)) & 1)
                position += 1
            }
            return value
        }
        mutating func skipUVLC() throws {
            for count in 0..<32 {
                if try read(1) != 0 { _ = try read(count); return }
            }
        }
    }
}
