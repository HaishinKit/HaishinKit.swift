import AVFoundation

/// Decodes a single Enhanced RTMP Opus sequence, including ID-header trimming/gain.
/// Keeping this state in RTMP avoids changing other transports' audio decoding.
final class RTMPOpusDecoder {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let gain: Float
    private let preSkip: Int
    private var remainingSkip: Int
    private var decodedFrames: Int64 = 0
    private var inputFrames: Int64 = 0
    private var firstSampleTime: Int64?

    init?(header: OpusHeaderPacket) {
        guard let input = header.makeAudioFormat(),
              let output = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: UInt32(header.channels)),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        inputFormat = input
        outputFormat = output
        self.converter = converter
        preSkip = Int(header.preSkip)
        remainingSkip = preSkip
        gain = pow(10, Float(header.outputGain) / (20 * 256))
    }

    func decode(_ data: Data, when: AVAudioTime) -> (AVAudioPCMBuffer, AVAudioTime)? {
        guard let frames = Self.frameCount(data) else { return nil }
        let input = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: data.count)
        input.byteLength = UInt32(data.count)
        input.packetCount = 1
        input.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0,
            mVariableFramesInPacket: frames, mDataByteSize: input.byteLength)
        data.copyBytes(to: input.data.assumingMemoryBound(to: UInt8.self), count: data.count)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 5760) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { return nil }
        let packetTime = Int64((AVAudioTime.seconds(forHostTime: when.hostTime) * 48_000).rounded())
        if firstSampleTime == nil {
            firstSampleTime = packetTime
        } else if let firstSampleTime {
            let difference = packetTime - (firstSampleTime + inputFrames)
            // RTMP timestamps have millisecond precision. Preserve real source gaps.
            if abs(difference) > 48 { self.firstSampleTime = firstSampleTime + difference }
        }
        inputFrames += Int64(frames)
        guard output.frameLength > 0 else { return nil }
        let skip = min(remainingSkip, Int(output.frameLength))
        let position = (firstSampleTime ?? 0) + decodedFrames + Int64(skip - preSkip)
        decodedFrames += Int64(output.frameLength)
        remainingSkip -= skip
        let length = Int(output.frameLength) - skip
        guard length > 0, let channels = output.floatChannelData else { return nil }
        for channel in 0..<Int(outputFormat.channelCount) {
            for index in 0..<length { channels[channel][index] = channels[channel][index + skip] * gain }
        }
        output.frameLength = UInt32(length)
        return (output, AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(0, Double(position) / 48_000)),
            sampleTime: position, atRate: 48_000))
    }

    /// RFC 6716 packet duration, bounded to 120 ms. The decoder validates framing.
    static func frameCount(_ data: Data) -> UInt32? {
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
}
