import AOMHaishinKit
import AVFoundation
import Testing

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPAV1PublishingTests {
    @Test func realAOMPacketsRoundTripThroughEnhancedRTMP() throws {
        let encoder = try AOMVideoEncoder(settings: .init(videoSize: CGSize(width: 64, height: 48), bitRate: 200_000))
        let decoder = try AOMVideoDecoder()
        defer { encoder.invalidate(); decoder.invalidate() }
        var packets: [CMSampleBuffer] = []
        for index in 0..<5 { packets += try encoder.encode(frame(index)) }
        packets += try encoder.finish()
        #expect(packets.count == 5)
        var decoded = 0
        for (index, packet) in packets.enumerated() {
            let format = try #require(packet.formatDescription)
            let atoms = try #require(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data])
            let encodedConfiguration = try #require(atoms["av1C"])
            let record = try #require(AV1DecoderConfigurationRecord(data: encodedConfiguration))
            _ = try #require(record.makeFormatDescription(), "av1C: \(encodedConfiguration as NSData)")
            let sequence = try #require(RTMPVideoMessage(streamId: 1, timestamp: 0, formatDescription: format))
            #expect(Array(sequence.payload.prefix(5)) == [0x90, 0x61, 0x76, 0x30, 0x31])
            let configuration = Data(sequence.payload.dropFirst(5))
            #expect(configuration[0] == 0x81)
            #expect(configuration[2] & 0x7F == 0x0C)
            let receivedFormat = try #require(sequence.makeFormatDescription())
            #expect(CMVideoFormatDescriptionGetDimensions(receivedFormat).width == 64)
            #expect(CMVideoFormatDescriptionGetDimensions(receivedFormat).height == 48)
            let sent = try #require(RTMPVideoMessage(streamId: 1, timestamp: UInt32(index * 33), sampleBuffer: packet))
            #expect(sent.videoFourCC == .av1)
            #expect(sent.packetType == RTMPVideoPacketType.codedFrames.rawValue)
            #expect(sent.compositionTime == 0)
            #expect(sent.payload.count == packet.totalSampleSize + 5)
            #expect(try Data(sent.payload.dropFirst(5)) == packet.dataBuffer?.dataBytes())
            let received = try #require(sent.makeSampleBuffer(packet.presentationTimeStamp, formatDesciption: receivedFormat))
            #expect(received.isNotSync == packet.isNotSync)
            let frames = try decoder.decode(received)
            decoded += frames.count
            let pixel = try #require(frames.first?.imageBuffer)
            #expect(CVPixelBufferGetWidth(pixel) == 64)
            #expect(CVPixelBufferGetHeight(pixel) == 48)
            #expect(frames.first?.presentationTimeStamp == packet.presentationTimeStamp)
        }
        #expect(decoded == packets.count)
        #expect(packets.contains { $0.isNotSync })
    }

    @Test func configurationIsRequiredForPublishing() throws {
        var description: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_AV1,
            width: 64, height: 48, extensions: nil, formatDescriptionOut: &description) == noErr)
        #expect(RTMPVideoMessage(streamId: 1, timestamp: 0, formatDescription: description) == nil)
    }

    @Test func streamAcceptsAOMOutputStartingAtZero() async throws {
        let encoder = try AOMVideoEncoder(settings: .init(videoSize: CGSize(width: 64, height: 48)))
        defer { encoder.invalidate() }
        let first = try #require(encoder.encode(frame(0)).first)
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let publishing = Task { try await stream.publish("av1", metadata: { _ in nil }) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while await stream.readyState != .publish && ContinuousClock.now < deadline { await Task.yield() }
        try #require(await stream.readyState == .publish)
        await stream.dispatch(status("NetStream.Publish.Start"), type: .zero)
        _ = try await publishing.value
        let publishCommand = RTMPCommandMessage(streamId: 0, transactionId: 0, objectEncoding: .amf0,
            commandName: "publish", commandObject: nil, arguments: ["av1", "live"])
        let before = publishCommand.payload.count + status("NetStream.Publish.Start").payload.count
        while await stream.info.byteCount < before && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(await stream.info.byteCount == before)
        await stream.append(first)
        let configuration = try #require(RTMPVideoMessage(streamId: 0, timestamp: 0, formatDescription: first.formatDescription))
        let coded = try #require(RTMPVideoMessage(streamId: 0, timestamp: 0, sampleBuffer: first))
        let expected = before + configuration.payload.count + coded.payload.count
        let outputDeadline = ContinuousClock.now.advanced(by: .seconds(30))
        while await stream.info.byteCount < expected && ContinuousClock.now < outputDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await stream.info.byteCount == expected)
        let closing = Task { try await stream.close() }
        while await stream.readyState != .idle && ContinuousClock.now < outputDeadline { await Task.yield() }
        await stream.dispatch(status("NetStream.Unpublish.Success"), type: .zero)
        _ = try await closing.value
    }

    private func status(_ code: String) -> RTMPCommandMessage {
        RTMPCommandMessage(streamId: 0, transactionId: 0, objectEncoding: .amf0,
            commandName: "onStatus", commandObject: nil, arguments: [["level": "status", "code": code] as AMFObject])
    }

    private func frame(_ index: Int) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_420YpCbCr8Planar, nil, &pixel) == kCVReturnSuccess)
        let image = try #require(pixel)
        CVPixelBufferLockBaseAddress(image, [])
        for plane in 0..<3 {
            let data = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
            memset(data, plane == 0 ? Int32(80 + index) : (plane == 1 ? 96 : 160),
                CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane))
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(index), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
