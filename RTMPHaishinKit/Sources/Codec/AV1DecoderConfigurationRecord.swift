import CoreMedia
import Foundation

/// AV1CodecConfigurationRecord, as defined by AV1-ISOBMFF section 2.3.
struct AV1DecoderConfigurationRecord {
    let data: Data

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0x81,
              bytes[1] >> 5 <= 2, bytes[3] & 0xE0 == 0,
              bytes[3] & 0x10 != 0 || bytes[3] & 0x0F == 0,
              bytes[2] & 0x20 == 0 || (bytes[1] >> 5 == 2 && bytes[2] & 0x40 != 0) else {
            return nil
        }
        self.data = Data(data)
    }

    /// A record may omit configOBUs; in that case obtain dimensions from the first sync sample.
    func makeFormatDescription(inBand data: Data = Data()) -> CMFormatDescription? {
        let configuredSequence = Self.sequenceHeader(in: self.data.dropFirst(4))
        guard let sequence = configuredSequence ?? Self.sequenceHeader(in: data),
              sequence.payload.first.map({ $0 >> 5 }) == self.data[1] >> 5,
              let dimensions = try? Self.dimensions(sequence.payload) else {
            return nil
        }
        // VideoToolbox creates its decoder before seeing the first sample. Give it
        // the in-band sequence header in av1C as well, ahead of any metadata OBUs.
        let configuration = configuredSequence == nil ?
            Data(self.data.prefix(4)) + sequence.obu + self.data.dropFirst(4) : self.data
        var description: CMFormatDescription?
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["av1C": configuration]
        ]
        guard CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_AV1,
            width: dimensions.width, height: dimensions.height,
            extensions: extensions as CFDictionary, formatDescriptionOut: &description
        ) == noErr else {
            return nil
        }
        return description
    }

    private static func sequenceHeader(in data: Data) -> (payload: Data, obu: Data)? {
        let bytes = [UInt8](data)
        var position = 0
        while position < bytes.count {
            let start = position
            let header = bytes[position]
            position += 1
            // Low-overhead OBUs must carry a size; reject forbidden/reserved header bits.
            guard header & 0x83 == 0x02 else { return nil }
            if header & 0x04 != 0 {
                guard position < bytes.count, bytes[position] & 0x07 == 0 else { return nil }
                position += 1
            }
            var size: UInt64 = 0
            var terminated = false
            for index in 0..<8 {
                guard position < bytes.count else { return nil }
                let byte = bytes[position]
                position += 1
                size |= UInt64(byte & 0x7F) << (index * 7)
                if byte & 0x80 == 0 {
                    terminated = true
                    break
                }
            }
            guard terminated, size <= UInt64(bytes.count - position) else { return nil }
            if (header >> 3) & 0x0F == 1 {
                return (Data(bytes[position..<(position + Int(size))]), Data(bytes[start..<(position + Int(size))]))
            }
            position += Int(size)
        }
        return nil
    }

    /// Read the sequence-header prefix through max_frame_{width,height}_minus_1.
    private static func dimensions(_ data: Data) throws -> (width: Int32, height: Int32) {
        var bits = Bits(bytes: [UInt8](data))
        guard try bits.read(3) <= 2 else { throw Bits.Error.invalidData }
        let stillPicture = try bits.read(1)
        let reduced = try bits.read(1) != 0
        if reduced {
            guard stillPicture == 1 else { throw Bits.Error.invalidData }
            _ = try bits.read(5)
        } else {
            var bufferDelayLength = 0
            if try bits.read(1) != 0 { // timing_info_present_flag
                _ = try bits.read(32) // num_units_in_display_tick
                _ = try bits.read(32) // time_scale
                if try bits.read(1) != 0 { try bits.skipUVLC() }
                if try bits.read(1) != 0 { // decoder_model_info_present_flag
                    bufferDelayLength = try bits.read(5) + 1
                    _ = try bits.read(32)
                    _ = try bits.read(5)
                    _ = try bits.read(5)
                }
            }
            let initialDelay = try bits.read(1) != 0
            let operatingPoints = try bits.read(5) + 1
            for _ in 0..<operatingPoints {
                _ = try bits.read(12)
                if try bits.read(5) > 7 { _ = try bits.read(1) }
                if bufferDelayLength > 0, try bits.read(1) != 0 {
                    _ = try bits.read(bufferDelayLength)
                    _ = try bits.read(bufferDelayLength)
                    _ = try bits.read(1)
                }
                if initialDelay, try bits.read(1) != 0 { _ = try bits.read(4) }
            }
        }
        let widthBits = try bits.read(4) + 1
        let heightBits = try bits.read(4) + 1
        return (Int32(try bits.read(widthBits) + 1), Int32(try bits.read(heightBits) + 1))
    }

    private struct Bits {
        enum Error: Swift.Error { case invalidData }
        let bytes: [UInt8]
        var position = 0

        mutating func read(_ count: Int) throws -> Int {
            guard (0...32).contains(count), count <= bytes.count * 8 - position else {
                throw Error.invalidData
            }
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | Int((bytes[position / 8] >> (7 - position % 8)) & 1)
                position += 1
            }
            return value
        }

        mutating func skipUVLC() throws {
            for leadingZeros in 0..<32 {
                if try read(1) != 0 {
                    _ = try read(leadingZeros)
                    return
                }
            }
        }
    }
}
