import AVFoundation
import HaishinKit

enum RTMPMessageType: UInt8 {
    case chunkSize = 0x01
    case abort = 0x02
    case ack = 0x03
    case user = 0x04
    case windowAck = 0x05
    case bandwidth = 0x06
    case audio = 0x08
    case video = 0x09
    case amf3Data = 0x0F
    case amf3Shared = 0x10
    case amf3Command = 0x11
    case amf0Data = 0x12
    case amf0Shared = 0x13
    case amf0Command = 0x14
    case aggregate = 0x16
}

protocol RTMPMessage: Sendable {
    var type: RTMPMessageType { get }
    var streamId: UInt32 { get }
    var timestamp: UInt32 { get }
    var payload: Data { get }
}

// MARK: -
/**
 5.4.1. Set Chunk Size (1)
 */
struct RTMPSetChunkSizeMessage: RTMPMessage {
    // MARK: RTMPMessage
    let type: RTMPMessageType = .chunkSize
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        size.bigEndian.data
    }
    // MARK: RTMPSetChunkSizeMessage
    let size: UInt32

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        size = UInt32(data: header.payload).bigEndian
    }

    init(size: UInt32) {
        self.streamId = 0
        self.size = size
        self.timestamp = 0
    }
}

// MARK: -
/**
 5.4.2. Abort Message (2)
 */
struct RTMPAbortMessge: RTMPMessage {
    // MARK: RTMPMessage
    let type: RTMPMessageType = .abort
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        chunkStreamId.bigEndian.data
    }
    // MARK: RTMPAbortMessge
    let chunkStreamId: UInt32

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        chunkStreamId = UInt32(data: header.payload).bigEndian
    }
}

// MARK: -
/**
 5.4.3. Acknowledgement (3)
 */
struct RTMPAcknowledgementMessage: RTMPMessage {
    // MARK: RTMPMessage
    let type: RTMPMessageType = .ack
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        sequence.bigEndian.data
    }
    // MARK: RTMPAcknowledgementMessage
    let sequence: UInt32

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        sequence = UInt32(data: header.payload).bigEndian
    }

    init(sequence: UInt32) {
        self.streamId = 0
        self.timestamp = 0
        self.sequence = sequence
    }
}

// MARK: -
/**
 5.4.4. Window Acknowledgement Size (5)
 */
struct RTMPWindowAcknowledgementSizeMessage: RTMPMessage {
    // MARK: RTMPMessage
    let type: RTMPMessageType = .windowAck
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        size.bigEndian.data
    }
    // MARK: RTMPWindowAcknowledgementSizeMessage
    let size: UInt32

    init(size: UInt32) {
        self.streamId = 0
        self.timestamp = 0
        self.size = size
    }

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        size = UInt32(data: header.payload).bigEndian
    }
}

// MARK: -
/**
 5.4.5. Set Peer Bandwidth (6)
 */
struct RTMPSetPeerBandwidthMessage: RTMPMessage {
    enum Limit: UInt8 {
        case hard = 0x00
        case soft = 0x01
        case dynamic = 0x02
        case unknown = 0xFF
    }

    // MARK: RTMPMessage
    let type: RTMPMessageType = .bandwidth
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        var payload = Data()
        payload.append(size.bigEndian.data)
        payload.append(limit.rawValue)
        return payload
    }

    // MARK: RTMPSetPeerBandwidthMessage
    let size: UInt32
    let limit: Limit

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        size = UInt32(data: header.payload[0..<4]).bigEndian
        limit = Limit(rawValue: header.payload[4]) ?? .unknown
    }
}

// MARK: -
/**
 7.1.1. Command Message (20, 17)
 */
struct RTMPCommandMessage: RTMPMessage {
    // MARK: RTMPMessage
    var type: RTMPMessageType {
        objectEncoding.commandType
    }
    let streamId: UInt32
    let timestamp: UInt32
    let payload: Data
    // MARK: RTMPCommandMessage
    let objectEncoding: RTMPObjectEncoding
    let commandName: String
    let transactionId: Int
    let commandObject: AMFObject?
    let arguments: [(any Sendable)?]

    init?(_ header: RTMPChunkMessageHeader, objectEncoding: RTMPObjectEncoding) {
        self.streamId = header.messageStreamId
        self.payload = header.payload
        self.timestamp = header.timestamp
        self.objectEncoding = objectEncoding
        let serializer = AMF0Serializer(data: payload)
        do {
            commandName = try serializer.deserialize()
            transactionId = try serializer.deserialize()
            commandObject = try serializer.deserialize()
            var arguments: [(any Sendable)?] = []
            if 0 < serializer.bytesAvailable {
                arguments.append(try serializer.deserialize())
            }
            self.arguments = arguments
        } catch {
            logger.error("\(serializer)")
            return nil
        }
    }

    init(streamId: UInt32, transactionId: Int, objectEncoding: RTMPObjectEncoding, commandName: String, commandObject: AMFObject?, arguments: [(any Sendable)?]) {
        self.transactionId = transactionId
        self.objectEncoding = objectEncoding
        self.commandName = commandName
        self.commandObject = commandObject
        self.arguments = arguments
        self.streamId = streamId
        self.timestamp = 0
        let serializer = AMF0Serializer()
        if objectEncoding.commandType == .amf3Command {
            serializer.writeUInt8(0)
        }
        serializer
            .serialize(commandName)
            .serialize(transactionId)
            .serialize(commandObject)
        for i in arguments {
            serializer.serialize(i)
        }
        self.payload = serializer.data
    }
}

// MARK: -
/**
 7.1.2. Data Message (18, 15)
 */
struct RTMPDataMessage: RTMPMessage {
    // MARK: RTMPMessage
    var type: RTMPMessageType {
        objectEncoding.dataType
    }
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data
    // MARK: RTMPDataMessage
    let objectEncoding: RTMPObjectEncoding
    let handlerName: String
    let arguments: [(any Sendable)?]

    init?(_ header: RTMPChunkMessageHeader, objectEncoding: RTMPObjectEncoding) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        payload = header.payload
        self.objectEncoding = objectEncoding
        let serializer = AMF0Serializer(data: header.payload)
        do {
            self.handlerName = try serializer.deserialize()
            var arguments: [(any Sendable)?] = []
            while 0 < serializer.bytesAvailable {
                arguments.append(try serializer.deserialize())
            }
            self.arguments = arguments
        } catch {
            logger.error("\(serializer)")
            return nil
        }
    }

    init(streamId: UInt32, objectEncoding: RTMPObjectEncoding, timestamp: UInt32, handlerName: String, arguments: [(any Sendable)?] = []) {
        self.objectEncoding = objectEncoding
        self.handlerName = handlerName
        self.arguments = arguments
        self.timestamp = timestamp
        self.streamId = streamId
        let serializer = AMF0Serializer()
        if objectEncoding.dataType == .amf3Command {
            serializer.writeUInt8(0)
        }
        _ = serializer
            .serialize(handlerName)
        for i in arguments {
            serializer.serialize(i)
        }
        self.payload = serializer.data
    }
}

// MARK: -
/**
 7.1.3. Shared Object Message (19, 16)
 */
struct RTMPSharedObjectMessage: RTMPMessage {
    // MARK: RTMPMessage
    var type: RTMPMessageType {
        return objectEncoding.sharedObjectType
    }
    let streamId: UInt32
    let timestamp: UInt32
    let payload: Data

    // MARK: RTMPSharedObjectMessage
    let objectEncoding: RTMPObjectEncoding
    let sharedObjectName: String
    let currentVersion: UInt32
    let flags: Data
    let events: [RTMPSharedObjectEvent]

    init?(_ header: RTMPChunkMessageHeader, objectEncoding: RTMPObjectEncoding) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        payload = header.payload
        self.objectEncoding = objectEncoding

        var serializer: any AMFSerializer = AMF0Serializer(data: payload)
        do {
            if objectEncoding == .amf3 {
                serializer.position = 1
            }
            sharedObjectName = try serializer.readUTF8()
            currentVersion = try serializer.readUInt32()
            flags = try serializer.readBytes(8)
            var events: [RTMPSharedObjectEvent] = []
            while 0 < serializer.bytesAvailable {
                if let event = try RTMPSharedObjectEvent(serializer: &serializer) {
                    events.append(event)
                }
            }
            self.events = events
        } catch {
            logger.error("\(serializer)")
            return nil
        }
    }

    init(timestamp: UInt32, streamId: UInt32, objectEncoding: RTMPObjectEncoding, sharedObjectName: String, currentVersion: UInt32, flags: Data, events: [RTMPSharedObjectEvent]) {
        self.timestamp = timestamp
        self.streamId = streamId
        self.objectEncoding = objectEncoding
        self.sharedObjectName = sharedObjectName
        self.currentVersion = currentVersion
        self.flags = flags
        self.events = events

        var serializer: any AMFSerializer = AMF0Serializer()
        if objectEncoding == .amf3 {
            serializer.writeUInt8(0)
        }

        serializer
            .writeUInt16(UInt16(sharedObjectName.utf8.count))
            .writeUTF8Bytes(sharedObjectName)
            .writeUInt32(currentVersion)
            .writeBytes(flags)
        for event in events {
            event.serialize(&serializer)
        }

        payload = serializer.data
    }
}

// MARK: -
/**
 7.1.5. Audio Message (9)
 */
struct RTMPAudioMessage: RTMPMessage {
    static let aacHeader: UInt8 =
        RTMPAudioCodec.aac.rawValue << 4 |
        RTMPSoundRate.kHz44.rawValue << 2 |
        RTMPSoundSize.snd16bit.rawValue << 1 |
        RTMPSoundType.stereo.rawValue

    // MARK: RTMPMessage
    let type: RTMPMessageType = .audio
    let streamId: UInt32
    let timestamp: UInt32
    let payload: Data

    // MARK: RTMPAudioMessage
    var codec: RTMPAudioCodec {
        return payload.isEmpty ? .unknown : RTMPAudioCodec(rawValue: payload[0] >> 4) ?? .unknown
    }

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        payload = header.payload
    }

    init?(streamId: UInt32, timestamp: UInt32, formatDescription: CMFormatDescription?) {
        self.streamId = streamId
        self.timestamp = timestamp
        switch formatDescription?.mediaSubType {
        case .opus:
            guard let header = OpusHeaderPacket(formatDescription: formatDescription) else {
                return nil
            }
            var buffer = Data([RTMPAudioCodec.exheader.rawValue << 4 | RTMPAudioPacketType.sequenceStart.rawValue])
            buffer.append(contentsOf: RTMPAudioFourCC.opus.rawValue.bigEndian.data)
            buffer.append(header.payload)
            self.payload = buffer
        default:
            guard let config = AudioSpecificConfig(formatDescription: formatDescription) else {
                return nil
            }
            var buffer = Data([Self.aacHeader, RTMPAACPacketType.seq.rawValue])
            buffer.append(contentsOf: config.bytes)
            self.payload = buffer
        }
    }

    init?(streamId: UInt32, timestamp: UInt32, audioBuffer: AVAudioCompressedBuffer?) {
        guard let audioBuffer else {
            return nil
        }
        self.streamId = streamId
        self.timestamp = timestamp
        switch audioBuffer.format.formatDescription.mediaSubType {
        case .opus:
            var buffer = Data([RTMPAudioCodec.exheader.rawValue << 4 | RTMPAudioPacketType.codedFrames.rawValue])
            buffer.append(contentsOf: RTMPAudioFourCC.opus.rawValue.bigEndian.data)
            buffer.append(audioBuffer.data.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.byteLength))
            self.payload = buffer
        default:
            var buffer = Data([Self.aacHeader, RTMPAACPacketType.raw.rawValue])
            buffer.append(audioBuffer.data.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.byteLength))
            self.payload = buffer
        }
    }

    func copyMemory(_ audioBuffer: AVAudioCompressedBuffer?) {
        payload.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress, let audioBuffer else {
                return
            }
            let byteCount = payload.count - codec.headerSize
            audioBuffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(byteCount))
            audioBuffer.packetCount = 1
            audioBuffer.byteLength = UInt32(byteCount)
            audioBuffer.data.copyMemory(from: baseAddress.advanced(by: codec.headerSize), byteCount: byteCount)
        }
    }

    func makeAudioFormat() -> AVAudioFormat? {
        switch payload[1] {
        case RTMPAACPacketType.seq.rawValue:
            let config = AudioSpecificConfig(bytes: [UInt8](payload[codec.headerSize..<payload.count]))
            return config?.makeAudioFormat()
        case RTMPAACPacketType.raw.rawValue:
            guard var audioStreamBasicDescription = codec.audioStreamBasicDescription(payload) else {
                return nil
            }
            return AVAudioFormat(streamDescription: &audioStreamBasicDescription)
        default:
            return nil
        }
    }
}

// MARK: -
/**
 7.1.5. Video Message (9)
 */
struct RTMPVideoMessage: RTMPMessage {
    static let ctsOffset = 0.066

    // MARK: RTMPMessage
    let type: RTMPMessageType = .video
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data

    // MARK: RTMPVideoMessage
    var isExHeader: Bool {
        return (payload[0] & 0b10000000) != 0
    }

    var packetType: UInt8 {
        return isExHeader ? payload[0] & 0b00001111 : payload[1]
    }

    var isSupported: Bool {
        return isExHeader ?
            payload[1] == 0x68 && payload[2] == 0x76 && payload[3] == 0x63 && payload[4] == 0x31 :
            payload[0] & 0b01110000 >> 4 == RTMPVideoCodec.avc.rawValue
    }

    var compositionTime: Int32 {
        let offset = self.offset
        var compositionTime = Int32(data: [0] + payload[2 + offset..<5 + offset]).bigEndian
        compositionTime <<= 8
        compositionTime /= 256
        return compositionTime
    }

    private var offset: Int {
        return isExHeader ? packetType == RTMPVideoPacketType.codedFrames.rawValue ? 3 : 0 : 0
    }

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        self.payload = header.payload
    }

    init?(streamId: UInt32, timestamp: UInt32, formatDescription: CMFormatDescription?) {
        guard let formatDescription else {
            return nil
        }
        self.streamId = streamId
        self.timestamp = timestamp
        switch formatDescription.mediaSubType {
        case .h264:
            guard let configurationBox = formatDescription.configurationBox else {
                return nil
            }
            var buffer = Data([RTMPFrameType.key.rawValue << 4 | RTMPVideoCodec.avc.rawValue, RTMPAVCPacketType.seq.rawValue, 0, 0, 0])
            buffer.append(configurationBox)
            payload = buffer
        case .hevc:
            guard let configurationBox = formatDescription.configurationBox else {
                return nil
            }
            var buffer = Data([0b10000000 | RTMPFrameType.key.rawValue << 4 | RTMPVideoPacketType.sequenceStart.rawValue, 0x68, 0x76, 0x63, 0x31])
            buffer.append(configurationBox)
            payload = buffer
        default:
            return nil
        }
    }

    init?(streamId: UInt32, timestamp: UInt32, sampleBuffer: CMSampleBuffer?) {
        guard let sampleBuffer, let data = try? sampleBuffer.dataBuffer?.dataBytes() else {
            return nil
        }
        self.streamId = streamId
        self.timestamp = timestamp
        let keyframe = !sampleBuffer.isNotSync
        switch sampleBuffer.formatDescription?.mediaSubType {
        case .h264:
            let compositionTime = sampleBuffer.getCompositionTime(Self.ctsOffset)
            var buffer = Data([((keyframe ? RTMPFrameType.key.rawValue : RTMPFrameType.inter.rawValue) << 4) | RTMPVideoCodec.avc.rawValue, RTMPAVCPacketType.nal.rawValue])
            buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
            buffer.append(data)
            payload = buffer
        case .hevc:
            let compositionTime = sampleBuffer.getCompositionTime(Self.ctsOffset)
            var buffer = Data([0b10000000 | ((keyframe ? RTMPFrameType.key.rawValue : RTMPFrameType.inter.rawValue) << 4) | RTMPVideoPacketType.codedFrames.rawValue, 0x68, 0x76, 0x63, 0x31])
            buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
            buffer.append(data)
            payload = buffer
        default:
            return nil
        }
    }

    func makeSampleBuffer(_ presentationTimeStamp: CMTime, formatDesciption: CMFormatDescription?) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        let blockBuffer = payload.makeBlockBuffer(advancedBy: RTMPTagType.video.headerSize + offset)
        var sampleSize = blockBuffer?.dataLength ?? 0
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: compositionTime == 0 ? presentationTimeStamp : CMTimeAdd(presentationTimeStamp, .init(value: CMTimeValue(compositionTime), timescale: 1000)),
            decodeTimeStamp: compositionTime == 0 ? .invalid : presentationTimeStamp
        )
        guard CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDesciption,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }
        sampleBuffer?.isNotSync = !(payload[0] >> 4 & 0b0111 == RTMPFrameType.key.rawValue)
        return sampleBuffer
    }

    func makeFormatDescription() -> CMFormatDescription? {
        if isExHeader {
            // hevc
            if payload[1] == 0x68 && payload[2] == 0x76 && payload[3] == 0x63 && payload[4] == 0x31 {
                var config = HEVCDecoderConfigurationRecord()
                config.data = payload.subdata(in: RTMPTagType.video.headerSize..<payload.count)
                return config.makeFormatDescription()
            }
        } else {
            if payload[0] & 0b01110000 >> 4 == RTMPVideoCodec.avc.rawValue {
                var config = AVCDecoderConfigurationRecord()
                config.data = payload.subdata(in: RTMPTagType.video.headerSize..<payload.count)
                return config.makeFormatDescription()
            }
        }
        return nil
    }
}

// MARK: -
/**
 7.1.6. Aggregate Message (22)
 */
struct RTMPAggregateMessage: RTMPMessage {
    // MARK: RTMPMessage
    let type: RTMPMessageType = .windowAck
    let streamId: UInt32
    let timestamp: UInt32
    let payload: Data

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        payload = header.payload
    }
}

// MARK: -
/**
 7.1.7. User Control Message Events
 */
struct RTMPUserControlMessage: RTMPMessage {
    enum Event: UInt8 {
        case streamBegin = 0x00
        case streamEof = 0x01
        case streamDry = 0x02
        case setBuffer = 0x03
        case recorded = 0x04
        case ping = 0x06
        case pong = 0x07
        case bufferEmpty = 0x1F
        case bufferFull = 0x20
        case unknown = 0xFF

        var bytes: [UInt8] {
            [0x00, rawValue]
        }
    }

    // MARK: RTMPMessage
    let type: RTMPMessageType = .user
    let streamId: UInt32
    let timestamp: UInt32
    var payload: Data {
        var data = Data()
        data += event.bytes
        data += value.bigEndian.data
        return data
    }

    // MARK: RTMPUserControlMessage
    let event: Event
    let value: Int32

    init(_ header: RTMPChunkMessageHeader) {
        streamId = header.messageStreamId
        timestamp = header.timestamp
        // A well-formed user control message is at least 6 bytes: a 2-byte
        // event type followed by a 4-byte value. A truncated payload from the
        // peer would otherwise index past the end of `payload` and trap
        // (EXC_BREAKPOINT / out of bounds), crashing the whole process from
        // the RTMP receive loop. Re-base to a 0-indexed copy (a Data slice
        // keeps its parent's indices) and bail out to a safe default when the
        // payload is too short.
        let payload = Data(header.payload)
        guard payload.count >= 6 else {
            event = .unknown
            value = 0
            return
        }
        event = Event(rawValue: payload[1]) ?? .unknown
        value = Int32(data: payload[2..<payload.count]).bigEndian
    }

    init(event: Event, value: Int32) {
        self.streamId = 0
        self.timestamp = 0
        self.event = event
        self.value = value
    }
}
