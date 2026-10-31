import Foundation

private let kRTMPExtendTimestampSize = 4

enum RTMPChunkError: Swift.Error {
    case bufferUnderflow
    case unknowChunkType(value: UInt8)
}

enum RTMPChunkType: UInt8 {
    case zero = 0
    case one = 1
    case two = 2
    case three = 3

    var headerSize: Int {
        switch self {
        case .zero:
            return 11
        case .one:
            return 7
        case .two:
            return 3
        case .three:
            return 0
        }
    }
}

enum RTMPChunkStreamId: UInt16 {
    case control = 0x02
    case command = 0x03
    case audio = 0x04
    case video = 0x05
    case data = 0x08
}

final class RTMPChunkMessageHeader {
    static let chunkSize = 128
    static let maxTimestamp: UInt32 = 0xFFFFFF

    var timestamp: UInt32 = 0
    // Type 3 chunks inherit this flag even after timestamp is decoded or the message is reset.
    var hasExtendedTimestamp = false
    var messageLength: Int = 0 {
        didSet {
            guard payload.count != messageLength else {
                return
            }
            payload = Data(count: messageLength)
            position = 0
        }
    }
    var messageTypeId: UInt8 = 0
    var messageStreamId: UInt32 = 0
    private(set) var payload = Data()
    private var position = 0

    init() {
    }

    init(timestmap: UInt32, messageLength: Int, messageTypeId: UInt8, messageStreamId: UInt32) {
        self.timestamp = timestmap
        self.messageLength = messageLength
        self.messageTypeId = messageTypeId
        self.messageStreamId = messageStreamId
        self.payload = Data(count: messageLength)
    }

    func put(_ buffer: RTMPChunkBuffer, chunkSize: Int) throws {
        let length = min(chunkSize, messageLength - position)
        if buffer.remaining < length {
            throw RTMPChunkError.bufferUnderflow
        }
        self.payload.replaceSubrange(position..<position + length, with: buffer.get(length))
        position += length
    }

    func reset() {
        position = 0
    }

    func makeMessage() -> (any RTMPMessage)? {
        if position < payload.count {
            return nil
        }
        switch messageTypeId {
        case 0x01:
            return RTMPSetChunkSizeMessage(self)
        case 0x02:
            return RTMPAbortMessge(self)
        case 0x03:
            return RTMPAcknowledgementMessage(self)
        case 0x04:
            return RTMPUserControlMessage(self)
        case 0x05:
            return RTMPWindowAcknowledgementSizeMessage(self)
        case 0x06:
            return RTMPSetPeerBandwidthMessage(self)
        case 0x08:
            return RTMPAudioMessage(self)
        case 0x09:
            return RTMPVideoMessage(self)
        case 0x0F:
            return RTMPDataMessage(self, objectEncoding: .amf3)
        case 0x10:
            return RTMPSharedObjectMessage(self, objectEncoding: .amf3)
        case 0x11:
            return RTMPCommandMessage(self, objectEncoding: .amf3)
        case 0x12:
            return RTMPDataMessage(self, objectEncoding: .amf0)
        case 0x13:
            return RTMPSharedObjectMessage(self, objectEncoding: .amf0)
        case 0x14:
            return RTMPCommandMessage(self, objectEncoding: .amf0)
        case 0x16:
            return RTMPAggregateMessage(self)
        default:
            return nil
        }
    }
}

final class RTMPChunkBuffer {
    static let headerSize = 3 + 11 + 4

    var payload: Data {
        data[position..<length]
    }

    var chunkSize = RTMPChunkMessageHeader.chunkSize {
        didSet {
            guard oldValue < chunkSize else {
                return
            }
            let length = chunkSize - data.count
            if 0 < length {
                data += Data(count: length + Self.headerSize)
            }
        }
    }

    var remaining: Int {
        return length - position
    }

    var hasRemaining: Bool {
        return 0 < length - position
    }

    var position = 0

    private var data: Data
    private var length = 0

    init(chunkSize: Int = RTMPChunkMessageHeader.chunkSize) {
        self.data = Data(count: chunkSize + Self.headerSize)
        self.chunkSize = chunkSize
    }

    func flip() -> Self {
        length = position
        position = 0
        return self
    }

    func get(_ length: Int) -> Data {
        defer {
            position += length
        }
        return data[position..<position + length]
    }

    func getBasicHeader() throws -> (RTMPChunkType, UInt16) {
        if remaining < 1 {
            throw RTMPChunkError.bufferUnderflow
        }
        let rawValue = (data[position] & 0b11000000) >> 6
        guard let type = RTMPChunkType(rawValue: rawValue) else {
            throw RTMPChunkError.unknowChunkType(value: rawValue)
        }
        switch data[position] & 0b00111111 {
        case 0:
            if remaining < 2 {
                throw RTMPChunkError.bufferUnderflow
            }
            defer {
                position += 2
            }
            return (type, UInt16(data[position + 1]) + 64)
        case 1:
            if remaining < 3 {
                throw RTMPChunkError.bufferUnderflow
            }
            defer {
                position += 3
            }
            return (type, UInt16(data: data[position + 1...position + 2]) + 64)
        default:
            defer {
                position += 1
            }
            return (type, UInt16(data[position] & 0b00111111))
        }
    }

    func getMessageHeader(_ type: RTMPChunkType, messageHeader: RTMPChunkMessageHeader) throws {
        if remaining < type.headerSize {
            throw RTMPChunkError.bufferUnderflow
        }
        switch type {
        case .zero:
            messageHeader.timestamp = UInt32(data: data[position..<position + 3]).bigEndian
            messageHeader.messageLength = Int(Int32(data: data[position + 3..<position + 6]).bigEndian)
            messageHeader.messageTypeId = data[position + 6]
            messageHeader.messageStreamId = UInt32(data: data[position + 7..<position + 11])
            position += type.headerSize
        case .one:
            messageHeader.timestamp = UInt32(data: data[position..<position + 3]).bigEndian
            messageHeader.messageLength = Int(Int32(data: data[position + 3..<position + 6]).bigEndian)
            messageHeader.messageTypeId = data[position + 6]
            position += type.headerSize
        case .two:
            messageHeader.timestamp = UInt32(data: data[position..<position + 3]).bigEndian
            position += type.headerSize
        case .three:
            break
        }

        if type != .three {
            messageHeader.hasExtendedTimestamp = messageHeader.timestamp == RTMPChunkMessageHeader.maxTimestamp
        }
        if messageHeader.hasExtendedTimestamp {
            if remaining < kRTMPExtendTimestampSize {
                throw RTMPChunkError.bufferUnderflow
            }
            messageHeader.timestamp = UInt32(data: data[position..<position + 4]).bigEndian
            position += kRTMPExtendTimestampSize
        }

        try messageHeader.put(self, chunkSize: chunkSize)
    }

    func put(_ data: Data) {
        let payload = payload
        let length = payload.count
        if self.data.count < data.count + length {
            self.data = Data(count: data.count + length)
        }
        self.data.replaceSubrange(0..<length, with: payload)
        self.data.replaceSubrange(length..<length + data.count, with: data)
        position = 0
        self.length = length + data.count
    }

    func putMessage(_ chunkType: RTMPChunkType, chunkStreamId: UInt16, message: some RTMPMessage) -> AnyIterator<Data> {
        let payload = message.payload
        let length = payload.count
        var offset = 0
        var remaining = min(chunkSize, length)
        return AnyIterator { () -> Data? in
            guard 0 < remaining else {
                return nil
            }
            defer {
                self.position = 0
                offset += remaining
                remaining = min(self.chunkSize, length - offset)
            }
            if offset == 0 {
                self.putBasicHeader(chunkType, chunkStreamId: chunkStreamId)
                self.putMessageHeader(chunkType, length: length, message: message)
            } else {
                self.putBasicHeader(.three, chunkStreamId: chunkStreamId)
            }
            self.data.replaceSubrange(self.position..<self.position + remaining, with: payload[offset..<offset + remaining])
            return self.data.subdata(in: 0..<self.position + remaining)
        }
    }

    private func putBasicHeader(_ chunkType: RTMPChunkType, chunkStreamId: UInt16) {
        if chunkStreamId <= 63 {
            data[position] = chunkType.rawValue << 6 | UInt8(chunkStreamId)
            position += 1
            return
        }
        if chunkStreamId <= 319 {
            data[position + 0] = chunkType.rawValue << 6 | 0b0000000
            data[position + 1] = UInt8(chunkStreamId - 64)
            position += 2
            return
        }
        data[position + 0] = chunkType.rawValue << 6 | 0b00000001
        let streamId = (chunkStreamId - 64).bigEndian.data
        data[position + 1] = streamId[0]
        data[position + 2] = streamId[1]
        position += 3
    }

    private func putMessageHeader(_ chunkType: RTMPChunkType, length: Int, message: some RTMPMessage) {
        switch chunkType {
        case .zero:
            data.replaceSubrange(position..<position + 3, with: message.timestamp.bigEndian.data[1...3])
            position += 3
            data.replaceSubrange(position..<position + 3, with: UInt32(length).bigEndian.data[1...3])
            position += 3
            data[position] = message.type.rawValue
            position += 1
            data.replaceSubrange(position..<position + 4, with: message.streamId.littleEndian.data)
            position += 4
        case .one:
            data.replaceSubrange(position..<position + 3, with: message.timestamp.bigEndian.data[1...3])
            position += 3
            data.replaceSubrange(position..<position + 3, with: UInt32(length).bigEndian.data[1...3])
            position += 3
            data[position] = message.type.rawValue
            position += 1
        case .two:
            data.replaceSubrange(position...position + 3, with: message.timestamp.bigEndian.data[1...3])
            position += 3
        case .three:
            break
        }
    }
}

extension RTMPChunkMessageHeader: CustomDebugStringConvertible {
    // MARK: CustomStringConvertible
    var debugDescription: String {
        Mirror(reflecting: self).debugDescription
    }
}
