import Foundation
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPChunkAssemblyTests {
    @Test func fragmentedBasicHeader() throws {
        let headers: [(bytes: Data, id: UInt16)] = [
            (Data([0x02]), 2),
            (Data([0x00, 0x01]), 65),
            (Data([0x01, 0x01, 0x01]), 321)
        ]
        for header in headers {
            for split in 0..<header.bytes.count {
                let buffer = RTMPChunkBuffer()
                // Grow the backing storage so the partial header ends at its boundary.
                let prefix = Data(repeating: 0, count: RTMPChunkBuffer.headerSize + buffer.chunkSize + 1)
                buffer.put(prefix + header.bytes.prefix(split))
                _ = buffer.get(prefix.count)
                let position = buffer.position

                #expect(throws: RTMPChunkError.self) {
                    try buffer.getBasicHeader()
                }
                #expect(buffer.position == position)

                buffer.put(Data(header.bytes.dropFirst(split)))
                let (type, chunkStreamId) = try buffer.getBasicHeader()
                #expect(type == .zero)
                #expect(chunkStreamId == header.id)
                #expect(buffer.remaining == 0)
            }
        }
    }

    @Test(arguments: [RTMPChunkType.zero, .one, .two], [UInt32(0xFFFFFF), UInt32(0x1000000)])
    func fragmentedExtendedTimestamp(type: RTMPChunkType, timestamp: UInt32) throws {
        let payload = Data([0, 6, 0, 0, 0, 1])
        var firstChunk = Data([type.rawValue << 6 | 2, 0xFF, 0xFF, 0xFF])
        if type == .zero || type == .one {
            firstChunk.append(contentsOf: [0, 0, 6, 4])
        }
        if type == .zero {
            firstChunk.append(contentsOf: [0, 0, 0, 0])
        }
        let extendedTimestamp = timestamp.bigEndian.data
        firstChunk.append(extendedTimestamp)
        firstChunk.append(payload.prefix(4))
        let continuation = Data([0xC2]) + extendedTimestamp + payload.suffix(2)
        let bytes = firstChunk + continuation

        // Split at every header/body boundary, including partway through the
        // continuation's extended timestamp, then retry as listen(_:) does.
        for split in 0...bytes.count {
            let buffer = RTMPChunkBuffer(chunkSize: 4)
            let header = RTMPChunkMessageHeader(timestmap: 0, messageLength: 6, messageTypeId: 4, messageStreamId: 0)
            var messages: [RTMPUserControlMessage] = []
            for (index, fragment) in [Data(bytes.prefix(split)), Data(bytes.dropFirst(split))].enumerated() {
                buffer.put(fragment)
                var rollbackPosition = buffer.position
                do {
                    while buffer.hasRemaining {
                        rollbackPosition = buffer.position
                        let (chunkType, chunkStreamId) = try buffer.getBasicHeader()
                        #expect(chunkStreamId == 2)
                        try buffer.getMessageHeader(chunkType, messageHeader: header)
                        if let message = header.makeMessage() as? RTMPUserControlMessage {
                            messages.append(message)
                            header.reset()
                        }
                    }
                } catch RTMPChunkError.bufferUnderflow {
                    buffer.position = rollbackPosition
                }
                if index == 0 && split < bytes.count {
                    // The complete payload is not available until the last byte.
                    #expect(messages.isEmpty)
                }
            }
            let message = try #require(messages.first)
            #expect(messages.count == 1)
            #expect(message.timestamp == timestamp)
            #expect(message.event == .ping)
            #expect(message.value == 1)
            #expect(message.payload == payload)
            #expect(buffer.remaining == 0)
        }
    }

    @Test func extendedTimestampPersistsUntilNextMessageHeader() throws {
        let buffer = RTMPChunkBuffer()
        let header = RTMPChunkMessageHeader()
        let payload = Data([0, 6, 0, 0, 0, 1])
        let extendedTimestamp = UInt32(0x1000000).bigEndian.data
        let first = Data([2, 0xFF, 0xFF, 0xFF, 0, 0, 6, 4, 0, 0, 0, 0]) + extendedTimestamp + payload
        let inherited = Data([0xC2]) + extendedTimestamp + payload
        let withoutExtension = Data([0x82, 0, 0, 1]) + payload
        let inheritedWithoutExtension = Data([0xC2]) + payload

        buffer.put(first + inherited + withoutExtension + inheritedWithoutExtension)
        for timestamp: UInt32 in [0x1000000, 0x1000000, 1, 1] {
            let (type, chunkStreamId) = try buffer.getBasicHeader()
            #expect(chunkStreamId == 2)
            try buffer.getMessageHeader(type, messageHeader: header)
            let message = try #require(header.makeMessage() as? RTMPUserControlMessage)
            #expect(message.timestamp == timestamp)
            #expect(message.payload == payload)
            header.reset()
        }
        #expect(buffer.remaining == 0)
    }
}
