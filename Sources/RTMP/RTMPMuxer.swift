import AVFoundation

// MARK: -
final class RTMPMuxer {
    static let aac: UInt8 = FLVAudioCodec.aac.rawValue << 4 | FLVSoundRate.kHz44.rawValue << 2 | FLVSoundSize.snd16bit.rawValue << 1 | FLVSoundType.stereo.rawValue

    var audioFormat: AVAudioFormat? {
        didSet {
            switch stream?.readyState {
            case .publishing:
                guard let config = AudioSpecificConfig(formatDescription: audioFormat?.formatDescription) else {
                    return
                }
                var buffer = Data([RTMPMuxer.aac, FLVAACPacketType.seq.rawValue])
                buffer.append(contentsOf: config.bytes)
                stream?.doOutput(
                    oldValue == nil ? .zero : .one,
                    chunkStreamId: FLVTagType.audio.streamId,
                    message: RTMPAudioMessage(streamId: 0, timestamp: 0, payload: buffer)
                )
            case .playing:
                if let audioFormat {
                    audioBuffer = AVAudioCompressedBuffer(format: audioFormat, packetCapacity: 1, maximumPacketSize: 1024 * Int(audioFormat.channelCount))
                } else {
                    audioBuffer = nil
                }
            default:
                break
            }
        }
    }

    var videoFormat: CMFormatDescription? {
        didSet {
            switch stream?.readyState {
            case .publishing:
                switch videoFormat?.mediaSubType {
                case .h264?:
                    guard let configurationBox = videoFormat?.configurationBox else {
                        return
                    }
                    var buffer = Data([FLVFrameType.key.rawValue << 4 | FLVVideoCodec.avc.rawValue, FLVAVCPacketType.seq.rawValue, 0, 0, 0])
                    buffer.append(configurationBox)
                    stream?.doOutput(
                        oldValue == nil ? .zero : .one,
                        chunkStreamId: FLVTagType.video.streamId,
                        message: RTMPVideoMessage(streamId: 0, timestamp: 0, payload: buffer)
                    )
                case .hevc?:
                    guard let configurationBox = videoFormat?.configurationBox else {
                        return
                    }
                    var buffer = Data([0b10000000 | FLVFrameType.key.rawValue << 4 | FLVVideoPacketType.sequenceStart.rawValue, 0x68, 0x76, 0x63, 0x31])
                    buffer.append(configurationBox)
                    stream?.doOutput(
                        oldValue == nil ? .zero : .one,
                        chunkStreamId: FLVTagType.video.streamId,
                        message: RTMPVideoMessage(streamId: 0, timestamp: 0, payload: buffer)
                    )
                default:
                    break
                }
            case .playing:
                stream?.dispatch(.rtmpStatus, bubbles: false, data: RTMPStream.Code.videoDimensionChange.data(""))
            default:
                break
            }
        }
    }

    var isRunning: Atomic<Bool> = .init(false)
    private var audioBuffer: AVAudioCompressedBuffer?
    private var audioTimestamp: RTMPTimestamp<AVAudioTime> = .init()
    private var videoTimestamp: RTMPTimestamp<CMTime> = .init()
    private weak var stream: RTMPStream?

    init(_ stream: RTMPStream) {
        self.stream = stream
    }

    func append(_ message: RTMPAudioMessage, type: RTMPChunkType) {
        let payload = message.payload
        let codec = message.codec
        stream?.info.byteCount.mutate { $0 += Int64(payload.count) }
        audioTimestamp.update(message, chunkType: type)
        guard let stream, message.codec.isSupported else {
            return
        }
        switch payload[1] {
        case FLVAACPacketType.seq.rawValue:
            let config = AudioSpecificConfig(bytes: [UInt8](payload[codec.headerSize..<payload.count]))
            audioFormat = config?.makeAudioFormat()
        case FLVAACPacketType.raw.rawValue:
            if audioFormat == nil {
                audioFormat = message.makeAudioFormat()
            }
            payload.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let baseAddress = buffer.baseAddress, let audioBuffer else {
                    return
                }
                let byteCount = payload.count - codec.headerSize
                audioBuffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(byteCount))
                audioBuffer.packetCount = 1
                audioBuffer.byteLength = UInt32(byteCount)
                audioBuffer.data.copyMemory(from: baseAddress.advanced(by: codec.headerSize), byteCount: byteCount)
                stream.mixer.audioIO.append(0, buffer: audioBuffer, when: audioTimestamp.value)
            }
        default:
            break
        }
    }

    func append(_ message: RTMPVideoMessage, type: RTMPChunkType) {
        stream?.info.byteCount.mutate { $0 += Int64( message.payload.count) }
        videoTimestamp.update(message, chunkType: type)
        guard let stream, FLVTagType.video.headerSize <= message.payload.count && message.isSupported else {
            return
        }
        if message.isExHeader {
            // IsExHeader for Enhancing RTMP, FLV
            switch message.packetType {
            case FLVVideoPacketType.sequenceStart.rawValue:
                videoFormat = message.makeFormatDescription()
            case FLVVideoPacketType.codedFrames.rawValue:
                if let sampleBuffer = message.makeSampleBuffer(videoTimestamp.value, formatDesciption: videoFormat) {
                    stream.mixer.videoIO.append(0, buffer: sampleBuffer)
                }
            case FLVVideoPacketType.codedFramesX.rawValue:
                if let sampleBuffer = message.makeSampleBuffer(videoTimestamp.value, formatDesciption: videoFormat) {
                    stream.mixer.videoIO.append(0, buffer: sampleBuffer)
                }
            default:
                break
            }
        } else {
            switch message.packetType {
            case FLVAVCPacketType.seq.rawValue:
                videoFormat = message.makeFormatDescription()
            case FLVAVCPacketType.nal.rawValue:
                if let sampleBuffer = message.makeSampleBuffer(videoTimestamp.value, formatDesciption: videoFormat) {
                    stream.mixer.videoIO.append(0, buffer: sampleBuffer)
                }
            default:
                break
            }
        }
    }
}

extension RTMPMuxer: IOMuxer {
    // MARK: IOMuxer
    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        guard let stream, let audioBuffer = audioBuffer as? AVAudioCompressedBuffer else {
            return
        }
        do {
            let timedelta = try audioTimestamp.update(when)
            var buffer = Data([RTMPMuxer.aac, FLVAACPacketType.raw.rawValue])
            buffer.append(audioBuffer.data.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.byteLength))
            stream.doOutput(
                .one,
                chunkStreamId: FLVTagType.audio.streamId,
                message: RTMPAudioMessage(streamId: 0, timestamp: timedelta, payload: buffer)
            )
        } catch {
            logger.info(error)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let stream, let data = try? sampleBuffer.dataBuffer?.dataBytes() else {
            return
        }
        do {
            let keyframe = !sampleBuffer.isNotSync
            let decodeTimeStamp = sampleBuffer.decodeTimeStamp.isValid ? sampleBuffer.decodeTimeStamp : sampleBuffer.presentationTimeStamp
            let compositionTime = videoTimestamp.getCompositionTime(sampleBuffer)
            let timedelta = try videoTimestamp.update(decodeTimeStamp)
            stream.frameCount += 1
            switch sampleBuffer.formatDescription?.mediaSubType {
            case .h264?:
                var buffer = Data([((keyframe ? FLVFrameType.key.rawValue : FLVFrameType.inter.rawValue) << 4) | FLVVideoCodec.avc.rawValue, FLVAVCPacketType.nal.rawValue])
                buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
                buffer.append(data)
                stream.doOutput(
                    .one,
                    chunkStreamId: FLVTagType.video.streamId,
                    message: RTMPVideoMessage(streamId: 0, timestamp: timedelta, payload: buffer)
                )
            case .hevc?:
                var buffer = Data([0b10000000 | ((keyframe ? FLVFrameType.key.rawValue : FLVFrameType.inter.rawValue) << 4) | FLVVideoPacketType.codedFrames.rawValue, 0x68, 0x76, 0x63, 0x31])
                buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
                buffer.append(data)
                stream.doOutput(
                    .one,
                    chunkStreamId: FLVTagType.video.streamId,
                    message: RTMPVideoMessage(streamId: 0, timestamp: timedelta, payload: buffer)
                )
            default:
                break
            }
        } catch {
            logger.info(error)
        }
    }
}

extension RTMPMuxer: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        audioFormat = nil
        videoFormat = nil
        audioTimestamp.clear()
        videoTimestamp.clear()
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        isRunning.mutate { $0 = false }
    }
}
