import AVFoundation
import Testing
import VideoToolbox

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPAV1Tests {
    // FFmpeg/SVT-AV1: two 64x64 blue frames at 30 fps, remuxed to Enhanced FLV.
    // These are video tag payloads, not synthetic AV1 frame data.
    private let sequence = Data(base64Encoded: "kGF2MDGBAAwACgsCAAAFFX/8AvgAQA==")!
    private let keyframe = Data(base64Encoded: "kWF2MDEKCwIAAAUVf/xK+QBAMhUQALCCBRQggQAAAyUKqE5W02KJaRA=")!
    private let interframe = Data(base64Encoded: "oWF2MDEyEDACAAAAACMYAAACAAAAnFA=")!
    private let sequence10 = Data(base64Encoded: "kGF2MDGBAEwACgsCAAAFFX/8AvhAQA==")!
    private let keyframe10 = Data(base64Encoded: "kWF2MDEKCwIAAAUVf/xK+UBAMhUQAK0CBxwwwQAAAyT+aEHVtXOqGoQ=")!

    @Test func advertisesHardwareDecodeWithoutEncode() {
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        #expect(RTMPConnection.supportedFourCcList.contains("av01") == supported)
        if supported {
            #expect(RTMPConnection.supportedVideoFourCcInfoMap["av01"] as? Int == RTMPConnection.FourCcInfoMask.canDecode.rawValue)
        } else {
            #expect(RTMPConnection.supportedVideoFourCcInfoMap["av01"] == nil)
        }
        #expect(RTMPStream.supportedVideoCodecs == [.h264, .hevc])
    }

    @Test(arguments: [false, true], [false, true])
    func parsesSequenceAndPreservesCodedOBUs(tenBit: Bool, codedFramesX: Bool) throws {
        let message = message(tenBit ? sequence10 : sequence)
        #expect(message.isSupported)
        let format = try #require(message.makeFormatDescription())
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AV1)
        #expect(CMVideoFormatDescriptionGetDimensions(format).width == 64)
        #expect(CMVideoFormatDescriptionGetDimensions(format).height == 64)
        #expect(format.isCompressed)
        let atoms = try #require(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data])
        #expect(atoms["av1C"] == Data((tenBit ? sequence10 : sequence).dropFirst(5)))
        var frameData = tenBit ? keyframe10 : keyframe
        if codedFramesX { frameData[0] = 0x93 }
        let frame = self.message(frameData)
        #expect(frame.compositionTime == 0)
        let pts = CMTime(value: 1234, timescale: 1000)
        let sample = try #require(frame.makeSampleBuffer(pts, formatDesciption: format))
        #expect(sample.presentationTimeStamp == pts)
        #expect(sample.decodeTimeStamp == .invalid)
        #expect(!sample.isNotSync)
        #expect(try sample.dataBuffer?.dataBytes() == Data(frameData.dropFirst(5)))
        var interData = interframe
        if codedFramesX { interData[0] = 0xA3 }
        let inter = try #require(self.message(interData).makeSampleBuffer(.init(value: 1267, timescale: 1000), formatDesciption: format))
        #expect(inter.isNotSync)
        #expect(try inter.dataBuffer?.dataBytes() == Data(interframe.dropFirst(5)))
    }

    @Test func configurationWithoutOBUsWaitsForInBandSequence() throws {
        let config = try #require(AV1DecoderConfigurationRecord(data: Data(sequence[5..<9])))
        #expect(config.makeFormatDescription() == nil)
        #expect(config.makeFormatDescription(inBand: Data(interframe.dropFirst(5))) == nil)
        let format = try #require(config.makeFormatDescription(inBand: Data(keyframe.dropFirst(5))))
        #expect(CMVideoFormatDescriptionGetDimensions(format).width == 64)
        let atoms = try #require(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data])
        #expect(atoms["av1C"] == Data(sequence[5..<9]) + keyframe[5..<18])
    }

    @Test func rejectsTruncatedAndUnsupportedPackets() throws {
        for size in 0..<5 {
            let packet = message(Data(sequence.prefix(size)))
            #expect(!packet.isSupported)
            #expect(packet.makeFormatDescription() == nil)
            #expect(packet.makeSampleBuffer(.zero, formatDesciption: nil) == nil)
        }
        for size in 0..<sequence.count {
            #expect(message(Data(sequence.prefix(size))).makeFormatDescription() == nil)
        }
        for header: UInt8 in [0x94, 0x95, 0x96, 0x9F] {
            var payload = keyframe
            payload[0] = header
            #expect(!message(payload).isSupported)
        }
        let format = try #require(message(sequence).makeFormatDescription())
        #expect(message(Data(keyframe.prefix(5))).makeSampleBuffer(.zero, formatDesciption: format) == nil)
        #expect(message(sequence).makeSampleBuffer(.zero, formatDesciption: format) == nil)
        #expect(message(keyframe).makeSampleBuffer(.zero, formatDesciption: nil) == nil)
        var otherFormat: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_H264, width: 64, height: 64, extensions: nil, formatDescriptionOut: &otherFormat) == noErr)
        #expect(message(keyframe).makeSampleBuffer(.zero, formatDesciption: otherFormat) == nil)
    }

    @Test func rejectsMalformedConfigurationAndOBUSizes() throws {
        let config = Data(sequence.dropFirst(5))
        for byte: UInt8 in [0, 1, 0x80, 0x82] {
            var invalid = config
            invalid[0] = byte
            #expect(AV1DecoderConfigurationRecord(data: invalid) == nil)
        }
        for obu in [[UInt8](repeating: 0xFF, count: 12), [0x0A, 0xFF], [0x0A, 0xFF, 0x7F], [0x08, 0], [0x8A, 0], [0x0E, 0x01, 0]] {
            let invalid = try #require(AV1DecoderConfigurationRecord(data: Data([0x81, 0, 0x0C, 0] + obu)))
            #expect(invalid.makeFormatDescription() == nil)
        }
    }

    @Test(arguments: [false, true])
    func readsDimensionsWithReducedOrTimedSequenceHeader(reduced: Bool) throws {
        var fields: [(Int, Int)] = [(0, 3), (reduced ? 1 : 0, 1), (reduced ? 1 : 0, 1)]
        if reduced {
            fields += [(0, 5)]
        } else {
            // Timing info, equal-picture-interval UVLC, decoder model, two operating points.
            fields += [(1, 1), (1, 32), (30, 32), (1, 1), (1, 1), (1, 1)]
            fields += [(3, 5), (1, 32), (0, 5), (0, 5), (1, 1), (1, 5)]
            fields += [(0, 12), (8, 5), (0, 1), (1, 1), (3, 4), (2, 4), (1, 1), (1, 1), (2, 4)]
            fields += [(0, 12), (0, 5), (0, 1), (0, 1)]
        }
        fields += [(5, 4), (5, 4), (63, 6), (31, 6)]
        // Only the dimension prefix is inspected here, not a decodable frame.
        var bits = fields.flatMap { value, count in (0..<count).reversed().map { (value >> $0) & 1 } }
        while !bits.count.isMultiple(of: 8) { bits.append(0) }
        var prefix = Data()
        for index in stride(from: 0, to: bits.count, by: 8) {
            prefix.append(UInt8(bits[index..<(index + 8)].reduce(0) { ($0 << 1) | $1 }))
        }
        let record = try #require(AV1DecoderConfigurationRecord(data: Data([0x81, 0, 0x0C, 0, 0x0A, UInt8(prefix.count)]) + prefix))
        let format = try #require(record.makeFormatDescription())
        #expect(CMVideoFormatDescriptionGetDimensions(format).width == 64)
        #expect(CMVideoFormatDescriptionGetDimensions(format).height == 32)
    }

    @Test(.enabled(if: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1), "Requires an AV1 hardware decoder"), arguments: [false, true], [false, true])
    func decodesRealFramesWithVideoToolbox(tenBit: Bool, inBandConfiguration: Bool) async throws {
        let configuration = Data((tenBit ? sequence10 : sequence).dropFirst(5))
        let record = try #require(AV1DecoderConfigurationRecord(data: inBandConfiguration ? Data(configuration.prefix(4)) : configuration))
        let format = try #require(record.makeFormatDescription(inBand: Data((tenBit ? keyframe10 : keyframe).dropFirst(5))))
        let codec = VideoCodec()
        let output = codec.outputStream
        codec.startRunning()
        defer { codec.stopRunning() }
        let packets = tenBit ? [keyframe10] : [keyframe, interframe]
        for (index, packet) in packets.enumerated() {
            let sample = try #require(message(packet).makeSampleBuffer(.init(value: Int64(index), timescale: 30), formatDesciption: format))
            codec.append(sample)
        }
        let session = try #require(codec.session) as! VTDecompressionSession
        #expect(VTDecompressionSessionFinishDelayedFrames(session) == noErr)
        #expect(VTDecompressionSessionWaitForAsynchronousFrames(session) == noErr)
        codec.stopRunning()
        var frames: [CMSampleBuffer] = []
        for await frame in output { frames.append(frame) }
        #expect(frames.count == packets.count)
        let image = try #require(frames.first?.imageBuffer)
        #expect(CVPixelBufferGetWidth(image) == 64)
        #expect(CVPixelBufferGetHeight(image) == 64)
        #expect(frames.first?.presentationTimeStamp == .zero)
    }

    @Test(.enabled(if: !VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1), "Requires a device without AV1 hardware decoding"))
    func unsupportedHardwareDoesNotUseSoftwareFallback() throws {
        let format = try #require(message(sequence).makeFormatDescription())
        let codec = VideoCodec()
        codec.startRunning()
        defer { codec.stopRunning() }
        codec.append(try #require(message(keyframe).makeSampleBuffer(.zero, formatDesciption: format)))
        #expect(codec.session == nil)
    }

    @Test(.enabled(if: !VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1), "Requires a device without AV1 hardware decoding"))
    func unsupportedVideoKeepsAACAudioPlaying() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let output = Output()
        await stream.addOutput(output)
        let playing = Task { try await stream.play("av1-with-aac") }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await stream.readyState != .play && ContinuousClock.now < startDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(await stream.readyState == .play)
        await stream.dispatch(status("NetStream.Play.Start"), type: .zero)
        _ = try await playing.value
        await stream.dispatch(message(sequence), type: .zero)
        await stream.dispatch(message(keyframe), type: .one)
        // FFmpeg AAC-LC: 48 kHz stereo configuration and a silent audio frame.
        await stream.dispatch(try audioMessage("rwARkFblAA==", timestamp: 0), type: .zero)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while output.counts.audio == 0 && ContinuousClock.now < deadline {
            await stream.dispatch(try audioMessage("rwEhEARgjBw=", timestamp: 21), type: .one)
            await stream.dispatch(message(interframe), type: .one)
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(output.counts.audio > 0)
        #expect(output.counts.video == 0)
        #expect(await stream.readyState == .playing)
        let closing = Task { try await stream.close() }
        let closeDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await stream.readyState != .idle && ContinuousClock.now < closeDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        await stream.dispatch(status("NetStream.Play.Stop"), type: .zero)
        _ = try await closing.value
    }

    private func status(_ code: String) -> RTMPCommandMessage {
        RTMPCommandMessage(streamId: 0, transactionId: 0, objectEncoding: .amf0,
                           commandName: "onStatus", commandObject: nil,
                           arguments: [["level": "status", "code": code] as AMFObject])
    }

    private func audioMessage(_ base64: String, timestamp: UInt32) throws -> RTMPAudioMessage {
        let data = try #require(Data(base64Encoded: base64))
        let buffer = RTMPChunkBuffer()
        buffer.put(data)
        let header = RTMPChunkMessageHeader(timestmap: timestamp, messageLength: data.count, messageTypeId: 8, messageStreamId: 0)
        try header.put(buffer, chunkSize: data.count)
        return RTMPAudioMessage(header)
    }

    private final class Output: StreamOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var audio = 0
        private var video = 0

        var counts: (audio: Int, video: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (audio, video)
        }

        func stream(_ stream: some StreamConvertible, didOutput buffer: AVAudioBuffer, when: AVAudioTime) {
            lock.lock()
            defer { lock.unlock() }
            if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 { audio += 1 }
        }

        func stream(_ stream: some StreamConvertible, didOutput buffer: CMSampleBuffer) {
            lock.lock()
            defer { lock.unlock() }
            video += 1
        }
    }

    private func message(_ payload: Data) -> RTMPVideoMessage {
        var message = RTMPVideoMessage(RTMPChunkMessageHeader())
        message.payload = payload
        return message
    }
}
