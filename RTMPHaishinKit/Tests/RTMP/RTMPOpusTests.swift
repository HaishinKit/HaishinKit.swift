@preconcurrency import AVFoundation
import Testing

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPOpusTests {
    @Test func advertisesOpusPlayback() {
        #expect(RTMPConnection.supportedAudioFourCcInfoMap["Opus"] as? Int == 3)
    }

    @Test(arguments: [1, 2])
    func parsesIDHeader(channels: Int) throws {
        let header = try #require(OpusHeaderPacket(data: idHeader(channels: channels)))
        #expect(header.channels == channels)
        let format = try #require(try message([0x90] + Array("Opus".utf8) + idHeader(channels: channels)).makeAudioFormat())
        #expect(format.sampleRate == 48_000)
        #expect(format.channelCount == channels)
    }

    @Test func rejectsMalformedHeadersAndPackets() throws {
        let valid = idHeader(channels: 2)
        for size in 0..<19 { #expect(OpusHeaderPacket(data: Data(valid.prefix(size))) == nil) }
        for (offset, value): (Int, UInt8) in [(0, 0), (8, 0), (8, 16), (9, 0), (9, 3), (18, 1)] {
            var bytes = valid
            bytes[offset] = value
            #expect(OpusHeaderPacket(data: bytes) == nil)
        }
        for bytes: [UInt8] in [[], [0x90], [0x90, 0x4F, 0x70], [0x90, 0x66, 0x4C, 0x61, 0x43]] {
            let packet = try message(bytes)
            #expect(!packet.isSupported)
            #expect(packet.makeAudioFormat() == nil)
        }
    }

    @Test func aacFormatAndCopyRemainSupported() throws {
        let sequence = try message([0xAF, 0, 0x11, 0x90])
        let format = try #require(sequence.makeAudioFormat())
        #expect(format.formatDescription.mediaSubType == .mpeg4AAC)
        let buffer = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: 8)
        #expect(try message([0xAF, 1, 1, 2, 3]).copyMemory(buffer))
        #expect(buffer.byteLength == 3)
        #expect(Array(UnsafeBufferPointer(start: buffer.data.assumingMemoryBound(to: UInt8.self), count: 3)) == [1, 2, 3])
        #expect(try !message([0xAF, 1] + Array(repeating: 1, count: 9)).copyMemory(buffer))
    }

    @Test func streamDecodesOpusAndRendersSound() async throws {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let pcmFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: pcmFormat, maximumFrameCount: 1024)
        _ = engine.mainMixerNode
        try engine.start()
        let player = AudioPlayer(audioEngine: engine)
        let stream = RTMPStream(connection: RTMPConnection())
        await stream.attachAudioPlayer(player)
        let playing = Task { try await stream.play("opus") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while await stream.readyState != .play && ContinuousClock.now < deadline { await Task.yield() }
        try #require(await stream.readyState == .play)
        await stream.dispatch(status("NetStream.Play.Start"), type: .zero)
        _ = try await playing.value
        await stream.dispatch(try message([0x90] + Array("Opus".utf8) + idHeader(channels: 1)), type: .zero)
        let output = Output()
        await stream.addOutput(output)
        let packets = try encode(channels: 1, count: 48)
        for packet in packets {
            await stream.dispatch(try message([0x91] + Array("Opus".utf8) + packet, timestamp: 20), type: .one)
            try await Task.sleep(for: .milliseconds(2))
        }
        while output.count < 20 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(output.count >= 20)
        let rendered = try #require(AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 1024))
        var peak: Float = 0
        for _ in 0..<24 {
            if try engine.renderOffline(1024, to: rendered) == .success {
                for index in 0..<Int(rendered.frameLength) { peak = max(peak, abs(rendered.floatChannelData![0][index])) }
            }
            await Task.yield()
        }
        #expect(peak > 0.1)
        await stream.dispatch(try message([0x92] + Array("Opus".utf8)), type: .one)
        let closing = Task { try await stream.close() }
        while await stream.readyState != .idle && ContinuousClock.now < deadline { await Task.yield() }
        await stream.dispatch(status("NetStream.Play.Stop"), type: .zero)
        _ = try await closing.value
        await stream.attachAudioPlayer(nil)
        withExtendedLifetime(player) {}
    }

    private func idHeader(channels: Int, skip: UInt16 = 0, gain: Int16 = 0) -> Data {
        Data(Array("OpusHead".utf8) + [1, UInt8(channels), UInt8(skip & 255), UInt8(skip >> 8),
            0x44, 0xAC, 0, 0, UInt8(UInt16(bitPattern: gain) & 255), UInt8(UInt16(bitPattern: gain) >> 8), 0])
    }

    private func encode(channels: Int, count: Int = 8) throws -> [Data] {
        let pcm = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: UInt32(channels)))
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatOpus,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 960, mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        let format = try #require(AVAudioFormat(streamDescription: &description))
        let encoder = try #require(AVAudioConverter(from: pcm, to: format))
        var result: [Data] = []
        for packet in 0..<count {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 960))
            input.frameLength = 960
            for channel in 0..<channels {
                for index in 0..<960 { input.floatChannelData![channel][index] = Float(sin(Double(packet * 960 + index) * 0.05)) * 0.3 }
            }
            let output = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: 4000)
            var supplied = false
            var error: NSError?
            _ = encoder.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return input
            }
            try #require(error == nil)
            if output.byteLength > 0 { result.append(Data(bytes: output.data, count: Int(output.byteLength))) }
        }
        return result
    }

    private func message(_ data: Data, timestamp: UInt32 = 0) throws -> RTMPAudioMessage {
        let buffer = RTMPChunkBuffer()
        buffer.put(data)
        let header = RTMPChunkMessageHeader(timestmap: timestamp, messageLength: data.count, messageTypeId: 8, messageStreamId: 0)
        try header.put(buffer, chunkSize: data.count)
        return RTMPAudioMessage(header)
    }

    private func message(_ bytes: [UInt8]) throws -> RTMPAudioMessage { try message(Data(bytes)) }

    private func status(_ code: String) -> RTMPCommandMessage {
        RTMPCommandMessage(streamId: 0, transactionId: 0, objectEncoding: .amf0,
            commandName: "onStatus", commandObject: nil, arguments: [["level": "status", "code": code] as AMFObject])
    }

    private final class Output: StreamOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func stream(_ stream: some StreamConvertible, didOutput buffer: CMSampleBuffer) {}
        func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
            lock.lock(); defer { lock.unlock() }; value += 1
        }
    }
}
