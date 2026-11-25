import AVFoundation

/// The AudioCodec translate audio data to another format.
/// - seealso: https://developer.apple.com/library/ios/technotes/tn2236/_index.html
final class AudioCodec {
    static let defaultFrameCapacity: UInt32 = 1024
    static let defaultInputBuffersCursor = 0

    var settings: AudioCodecSettings = .default {
        didSet {
            if settings.invalidateConverter(oldValue) {
                inputFormat = nil
            } else {
                settings.apply(audioConverter, oldValue: oldValue)
            }
        }
    }

    var outputFormat: AVAudioFormat? {
        return audioConverter?.outputFormat
    }

    @AsyncStreamedFlow
    var outputStream: AsyncStream<(AVAudioBuffer, AVAudioTime)>

    /// This instance is running to process(true) or not(false).
    private(set) var isRunning = false
    private(set) var inputFormat: AVAudioFormat? {
        didSet {
            guard inputFormat != oldValue else {
                return
            }
            if oldValue != nil { opusDecoding = OpusDecodingState() }
            inputBuffers.removeAll()
            inputBuffersCursor = Self.defaultInputBuffersCursor
            outputBuffers.removeAll()
            audioConverter = makeAudioConverter()
            for _ in 0..<settings.format.inputBufferCounts {
                if let inputBuffer = makeInputBuffer() {
                    inputBuffers.append(inputBuffer)
                }
            }
        }
    }
    private var opusDecoding = OpusDecodingState()
    private var audioTime = AudioTime()
    private var ringBuffer: AudioRingBuffer?
    private var inputBuffers: [AVAudioBuffer] = []
    private var outputBuffers: [AVAudioBuffer] = []
    private var audioConverter: AVAudioConverter?
    private var inputBuffersCursor = AudioCodec.defaultInputBuffersCursor

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else {
            return
        }
        switch settings.format {
        case .pcm:
            if let formatDescription = sampleBuffer.formatDescription, inputFormat?.formatDescription != formatDescription {
                inputFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            }
            var offset = 0
            var presentationTimeStamp = sampleBuffer.presentationTimeStamp
            for i in 0..<sampleBuffer.numSamples {
                guard let buffer = makeInputBuffer() as? AVAudioCompressedBuffer else {
                    continue
                }
                let sampleSize = CMSampleBufferGetSampleSize(sampleBuffer, at: i)
                let byteCount = sampleSize - ADTSHeader.size
                buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(byteCount))
                buffer.packetCount = 1
                buffer.byteLength = UInt32(byteCount)
                if let blockBuffer = sampleBuffer.dataBuffer {
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: offset + ADTSHeader.size, dataLength: byteCount, destination: buffer.data)
                    append(buffer, when: presentationTimeStamp.makeAudioTime())
                    presentationTimeStamp = CMTimeAdd(presentationTimeStamp, CMTime(value: CMTimeValue(1024), timescale: sampleBuffer.presentationTimeStamp.timescale))
                    offset += sampleSize
                }
            }
        default:
            break
        }
    }

    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        inputFormat = audioBuffer.format
        guard let audioConverter, isRunning else {
            return
        }
        if settings.format == .pcm, audioBuffer.format.formatDescription.mediaSubType == .opus,
           let compressed = audioBuffer as? AVAudioCompressedBuffer {
            decodeOpus(compressed, when: when, converter: audioConverter)
            return
        }
        var error: NSError?
        if let audioBuffer = audioBuffer as? AVAudioPCMBuffer {
            ringBuffer?.append(audioBuffer, when: when)
            if !audioTime.hasAnchor {
                audioTime.anchor(when.makeTime(), sampleRate: audioConverter.outputFormat.sampleRate)
            }
        }
        var outputStatus: AVAudioConverterOutputStatus = .endOfStream
        repeat {
            let outputBuffer = self.outputBuffer
            outputStatus = audioConverter.convert(to: outputBuffer, error: &error) { inNumberFrames, inputStatus in
                switch self.inputBuffer {
                case let inputBuffer as AVAudioCompressedBuffer:
                    inputBuffer.copy(audioBuffer)
                    inputStatus.pointee = .haveData
                    return inputBuffer
                case let inputBuffer as AVAudioPCMBuffer:
                    if self.ringBuffer?.isDataAvailable(inNumberFrames) == true {
                        inputBuffer.frameLength = inNumberFrames
                        _ = self.ringBuffer?.render(inNumberFrames, ioData: inputBuffer.mutableAudioBufferList)
                        inputStatus.pointee = .haveData
                        return inputBuffer
                    } else {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                default:
                    inputStatus.pointee = .noDataNow
                    return nil
                }
            }
            switch outputStatus {
            case .haveData:
                if audioTime.hasAnchor {
                    audioTime.advanced(AVAudioFramePosition(audioConverter.outputFormat.streamDescription.pointee.mFramesPerPacket))
                    _outputStream.yield((outputBuffer, audioTime.at))
                } else {
                    _outputStream.yield((outputBuffer, audioTime.at))
                }
                inputBuffersCursor += 1
                if inputBuffersCursor == inputBuffers.count {
                    inputBuffersCursor = Self.defaultInputBuffersCursor
                }
            default:
                releaseOutputBuffer(outputBuffer)
            }
        } while(outputStatus == .haveData && settings.format != .pcm)
    }

    /// Starts a new Opus sequence. Transports without an ID header can use append directly.
    func configureOpusDecoder(preSkip: UInt16 = 0, outputGain: Int16 = 0) {
        inputFormat = nil
        opusDecoding = OpusDecodingState(preSkip: preSkip, gain: pow(10, Float(outputGain) / (20 * 256)))
    }

    private struct OpusDecodingState {
        var preSkip: UInt16 = 0
        var gain: Float = 1
        var remainingSkip = 0
        var decodedFrames: Int64 = 0
        var inputFrames: Int64 = 0
        var firstSampleTime: Int64?
    }

    private func decodeOpus(_ buffer: AVAudioCompressedBuffer, when: AVAudioTime, converter: AVAudioConverter) {
        guard buffer.packetCount == 1, buffer.byteLength > 0, buffer.byteLength <= buffer.byteCapacity,
              buffer.byteLength <= 61_440 else { return }
        let data = Data(bytes: buffer.data, count: Int(buffer.byteLength))
        guard let frames = Self.opusFrameCount(data) else { return }
        let input = AVAudioCompressedBuffer(format: converter.inputFormat, packetCapacity: 1, maximumPacketSize: data.count)
        input.copy(buffer)
        input.packetDescriptions?.pointee.mVariableFramesInPacket = UInt32(Double(frames) * buffer.format.sampleRate / 48_000)
        let outputFormat = converter.outputFormat
        let rate = outputFormat.sampleRate
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: UInt32(ceil(rate * 0.12))) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { return }
        let seconds = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) :
            (when.isSampleTimeValid ? Double(when.sampleTime) / when.sampleRate : 0)
        let packetTime = Int64((seconds * rate).rounded())
        let preSkip = Int((Double(opusDecoding.preSkip) * rate / 48_000).rounded())
        if opusDecoding.firstSampleTime == nil {
            opusDecoding.firstSampleTime = packetTime
            opusDecoding.remainingSkip = preSkip
        } else if let first = opusDecoding.firstSampleTime {
            let difference = packetTime - (first + opusDecoding.inputFrames)
            // Allow millisecond timestamp rounding while preserving real source gaps.
            if abs(difference) > Int64(ceil(rate / 1000)) { opusDecoding.firstSampleTime = first + difference }
        }
        opusDecoding.inputFrames += Int64((Double(frames) * rate / 48_000).rounded())
        let skip = min(opusDecoding.remainingSkip, Int(output.frameLength))
        let position = (opusDecoding.firstSampleTime ?? 0) + opusDecoding.decodedFrames + Int64(skip - preSkip)
        opusDecoding.decodedFrames += Int64(output.frameLength)
        opusDecoding.remainingSkip -= skip
        let length = Int(output.frameLength) - skip
        guard length > 0, let channels = output.floatChannelData else { return }
        for channel in 0..<Int(outputFormat.channelCount) {
            for index in 0..<length { channels[channel][index] = channels[channel][index + skip] * opusDecoding.gain }
        }
        output.frameLength = UInt32(length)
        let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(0, Double(position) / rate)),
            sampleTime: position, atRate: rate)
        _outputStream.yield((output, time))
    }

    /// RFC 6716 packet duration on the 48 kHz Opus clock, bounded to 120 ms.
    static func opusFrameCount(_ data: Data) -> UInt32? {
        guard let toc = data.first, data.count <= 61_440 else { return nil }
        let frames: UInt32
        switch toc & 3 {
        case 0: frames = 1
        case 1, 2: frames = 2
        default:
            guard data.count > 1 else { return nil }
            frames = UInt32(data[data.startIndex + 1] & 63)
        }
        let samples: UInt32
        if toc & 128 != 0 { samples = 120 << ((toc >> 3) & 3) }
        else if toc & 96 == 96 { samples = toc & 8 == 0 ? 480 : 960 }
        else { samples = [480, 960, 1920, 2880][Int((toc >> 3) & 3)] }
        let total = samples * frames
        return frames > 0 && total <= 5760 ? total : nil
    }

    private func makeInputBuffer() -> AVAudioBuffer? {
        guard let inputFormat else {
            return nil
        }
        switch inputFormat.formatDescription.mediaSubType {
        case .linearPCM:
            let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.defaultFrameCapacity)
            buffer?.frameLength = Self.defaultFrameCapacity
            return buffer
        default:
            return AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: 1024)
        }
    }

    private func makeAudioConverter() -> AVAudioConverter? {
        guard
            let inputFormat,
            let outputFormat = settings.format.makeOutputAudioFormat(inputFormat, sampleRate: settings.sampleRate, channelMap: settings.channelMap) else {
            return nil
        }
        var converterInputFormat = inputFormat
        if settings.format == .pcm, inputFormat.formatDescription.mediaSubType == .opus {
            // RTP may describe 20-ms frames even when a packet contains more audio.
            // Opus duration comes from its TOC and packet description, not that hint.
            var description = inputFormat.streamDescription.pointee
            description.mFramesPerPacket = 0
            guard let variableFormat = AVAudioFormat(streamDescription: &description, channelLayout: inputFormat.channelLayout) else {
                return nil
            }
            converterInputFormat = variableFormat
        }
        let converter = AVAudioConverter(from: converterInputFormat, to: outputFormat)
        settings.apply(converter, oldValue: nil)
        if inputFormat.formatDescription.mediaSubType == .linearPCM {
            ringBuffer = AudioRingBuffer(inputFormat)
        }
        if self.outputFormat?.sampleRate != outputFormat.sampleRate {
            audioTime.reset()
        }
        if logger.isEnabledFor(level: .info) {
            logger.info("converter:", converter ?? "nil", ",inputFormat:", inputFormat, ",outputFormat:", outputFormat)
        }
        return converter
    }
}

extension AudioCodec: Codec {
    // MARK: Codec
    typealias Buffer = AVAudioBuffer

    var outputBuffer: AVAudioBuffer {
        guard let outputFormat = audioConverter?.outputFormat else {
            return .init()
        }
        if outputBuffers.isEmpty {
            for _ in 0..<settings.format.outputBufferCounts {
                outputBuffers.append(settings.format.makeAudioBuffer(outputFormat) ?? .init())
            }
        }
        return outputBuffers.removeFirst()
    }

    func releaseOutputBuffer(_ buffer: AVAudioBuffer) {
        outputBuffers.append(buffer)
    }

    private var inputBuffer: AVAudioBuffer {
        return inputBuffers[inputBuffersCursor]
    }
}

extension AudioCodec: Runner {
    // MARK: Running
    func startRunning() {
        guard !isRunning else {
            return
        }
        audioTime.reset()
        opusDecoding = OpusDecodingState()
        ringBuffer?.reset()
        audioConverter?.reset()
        isRunning = true
    }

    func stopRunning() {
        guard isRunning else {
            return
        }
        isRunning = false
        _outputStream.finish()
    }
}
