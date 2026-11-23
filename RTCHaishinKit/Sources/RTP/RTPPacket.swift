import AVFAudio
import Foundation

/// https://datatracker.ietf.org/doc/html/rfc3550
struct RTPPacket: Sendable {
    static let version: UInt8 = 2
    static let headerSize: Int = 12

    enum Error: Swift.Error {
        case bufferUnderrun
    }

    let version: UInt8
    let padding: Bool
    let `extension`: Bool
    let cc: UInt8
    let marker: Bool
    let payloadType: UInt8
    let sequenceNumber: UInt16
    let timestamp: UInt32
    let ssrc: UInt32
    let payload: Data
    var wireData: Data? = nil

    func copyBytes(to buffer: AVAudioCompressedBuffer) {
        let byteLength = UInt32(payload.count)
        buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: byteLength
        )
        buffer.packetCount = 1
        buffer.byteLength = byteLength
        payload.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return
            }
            buffer.data.copyMemory(from: baseAddress, byteCount: payload.count)
        }
    }
}

extension RTPPacket {
    var data: Data {
        if let wireData { return wireData }
        var data = Data()
        var first: UInt8 = (version & 0x03) << 6
        first |= (padding ? 1 : 0) << 5
        first |= (`extension` ? 1 : 0) << 4
        first |= cc & 0x0F
        data.append(first)
        var second: UInt8 = (marker ? 1 : 0) << 7
        second |= payloadType & 0x7F
        data.append(second)
        data.append(contentsOf: [
            UInt8(sequenceNumber >> 8),
            UInt8(sequenceNumber & 0xFF)
        ])
        data.append(contentsOf: [
            UInt8(timestamp >> 24),
            UInt8((timestamp >> 16) & 0xFF),
            UInt8((timestamp >> 8) & 0xFF),
            UInt8(timestamp & 0xFF)
        ])
        data.append(contentsOf: [
            UInt8(ssrc >> 24),
            UInt8((ssrc >> 16) & 0xFF),
            UInt8((ssrc >> 8) & 0xFF),
            UInt8(ssrc & 0xFF)
        ])
        data.append(payload)
        return data
    }

    init(_ data: Data) throws {
        guard RTPPacket.headerSize < data.count else {
            throw Error.bufferUnderrun
        }
        let first = data[0]
        version = (first & 0b11000000) >> 6
        padding = (first & 0b00100000) >> 5 == 1
        `extension` = (first & 0b00010000) >> 4 == 1
        cc = (first & 0b00001111)
        let second = data[1]
        marker = (second & 0b10000000) >> 7 == 1
        payloadType = (second & 0b01111111)
        sequenceNumber = UInt16(data[2]) << 8 | UInt16(data[3])
        timestamp = UInt32(data: data[4...7]).bigEndian
        ssrc = UInt32(data: data[8...11]).bigEndian
        guard version == Self.version else { throw Error.bufferUnderrun }
        var offset = Self.headerSize + Int(cc) * 4
        guard offset <= data.count else { throw Error.bufferUnderrun }
        if `extension` {
            guard offset + 4 <= data.count else { throw Error.bufferUnderrun }
            let words = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            offset += 4 + words * 4
        }
        var end = data.count
        if padding {
            guard let count = data.last, count > 0, Int(count) <= end - offset else { throw Error.bufferUnderrun }
            end -= Int(count)
        }
        guard offset < end else { throw Error.bufferUnderrun }
        payload = Data(data[offset..<end])
        wireData = data

    }
}
