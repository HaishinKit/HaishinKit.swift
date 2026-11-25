@preconcurrency import AVFoundation
import Testing

@testable import HaishinKit

@Suite struct AudioCodecOpusTests {
    @Test(arguments: [1, 2], [UInt32(0), 960])
    func decodesNativeOpusWithoutTransportHeader(channels: Int, framesPerPacket: UInt32) async throws {
        let packets = try encode(channels: channels)
        let output = try await decode(packets, channels: channels, framesPerPacket: framesPerPacket)
        #expect(output.count == packets.count)
        #expect(output.reduce(0) { $0 + Int($1.0.frameLength) } >= 960 * (packets.count - 1))
        #expect(output.contains { buffer, _ in
            (0..<Int(buffer.frameLength)).contains { abs(buffer.floatChannelData![0][$0]) > 0.1 }
        })
        let first = try #require(output.first)
        #expect(first.1.sampleTime == Int64(63_360_000))
        #expect(first.0.format.channelCount == channels)
    }

    @Test func appliesPreSkipAndGain() async throws {
        let packets = try encode(channels: 1)
        let plain = try await decode(packets, channels: 1)
        let adjusted = try await decode(packets, channels: 1, preSkip: 312, outputGain: -1536)
        let firstPlain = try #require(plain.first)
        let firstAdjusted = try #require(adjusted.first)
        #expect(firstAdjusted.0.frameLength + 312 == firstPlain.0.frameLength)
        #expect(firstAdjusted.1.sampleTime == firstPlain.1.sampleTime)
        let scale = pow(Float(10), -6 / 20)
        for index in 0..<Int(firstAdjusted.0.frameLength) {
            #expect(abs(firstAdjusted.0.floatChannelData![0][index] - firstPlain.0.floatChannelData![0][index + 312] * scale) < 0.00001)
        }
    }

    @Test func preSkipSpansPacketsAndGapsArePreserved() async throws {
        let output = try await decode(encode(channels: 1), channels: 1, preSkip: 2000, gap: true)
        let first = try #require(output.first)
        #expect(first.1.sampleTime == Int64(63_360_000))
        let times = output.map { $0.1.sampleTime }
        #expect(zip(times, times.dropFirst()).contains { $1 - $0 > 48_000 })
    }

    // FFmpeg/libopus 60-ms mono packet extracted from Enhanced FLV.
    @Test(arguments: [UInt32(0), 960])
    func decodesExternal60msPacket(framesPerPacket: UInt32) async throws {
        let data = Data(base64Encoded: "+wNySUcnEOTIW3gni4cywfAWFLzOloPklOYIBUI1IPndkrnvwWd6mU8VqSsGK9fpHcCqeUQLVpo9rErVBaagmdvGP6nngLNxsszgH+Hro1SwZmdhVZL7ohz6A3qkSq22wek0dWBURz2w5XcTKsncNcVow6h/RlFcyhBvzzk9W2xFANHcLk0yY03kk7iODRZzZuJkZUjmhlcc4NfhQY1yjBWv6R3t2sduSEBEYA8nMG7eAQN3Jer+Z5lbk9AV3IvlLyOBEOzuNA6CQl0kCjNt3th0H+S6obuFkk4yb7sx8Bd5M0lPMx95ZdPxlUAk1+iVc+BZ47uoDHZN6fw7qGBObcNRe9mncZl2jtkZxpmlNr1Z2jJ8pGBIw555dSyxMBA97sz2S1pQS1qtEMDB7qraRl5dQYCRU7+A8s50Hcc9E+6xoaDoHbwDNkt9CRpUbq2WVXT5FD5qqu9J+vuyF8pLvZ2R0bxq30drkbyEm9bzJrm8Y+Zw2/FJOXHaDO5VRLvqWQaqKt0HkGjM02N3ozA9z89pgKmbr1JPi9o6KfoVpy9+9ya86tbwLzLFOk+9StrG0Efw6TYyUNy2AaTIMQTUZdi8lcf+ELg6WoY2mvQny6Cfedw4XtgyZWITmU9H3e4=")!
        #expect(AudioCodec.opusFrameCount(data) == 2880)
        let output = try await decode([data], channels: 1, framesPerPacket: framesPerPacket, preSkip: 312)
        let first = try #require(output.first)
        #expect(first.0.frameLength > 2000)
        #expect((0..<Int(first.0.frameLength)).contains { abs(first.0.floatChannelData![0][$0]) > 0.05 })
    }

    @Test func malformedPacketsAreDropped() async throws {
        let output = try await decode([Data(), Data([0x83]), Data(repeating: 0xFF, count: 61_441)], channels: 1)
        #expect(output.isEmpty)
        #expect(AudioCodec.opusFrameCount(Data([0x83, 0])) == nil)
        #expect(AudioCodec.opusFrameCount(Data([0x9B, 63])) == nil)
        #expect(AudioCodec.opusFrameCount(Data([0x80])) == 120)
        #expect(AudioCodec.opusFrameCount(Data([0x98])) == 960)
        #expect(AudioCodec.opusFrameCount(Data([0x18])) == 2880)
    }

    @Test func reconfiguringSameFormatResetsSequenceState() async throws {
        let packets = try encode(channels: 1)
        let codec = AudioCodec()
        codec.settings.format = .pcm
        let stream = codec.outputStream
        codec.startRunning()
        codec.configureOpusDecoder(preSkip: 2000, outputGain: -1536)
        codec.append(try buffer(packets[0], channels: 1), when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        codec.configureOpusDecoder()
        codec.append(try buffer(packets[0], channels: 1), when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        codec.stopRunning()
        var count = 0
        for await (audio, when) in stream {
            let pcm = try #require(audio as? AVAudioPCMBuffer)
            #expect(pcm.frameLength > 500)
            #expect(when.sampleTime == 0)
            count += 1
        }
        #expect(count == 1)
    }

    @Test func stopAndRestartResetOpusDecoding() async throws {
        let packet = try #require(encode(channels: 1).first)
        let codec = AudioCodec()
        codec.settings.format = .pcm
        codec.startRunning()
        codec.configureOpusDecoder(preSkip: 2000, outputGain: -1536)
        codec.append(try buffer(packet, channels: 1), when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        codec.stopRunning()
        let stream = codec.outputStream
        codec.startRunning()
        codec.append(try buffer(packet, channels: 1), when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        codec.stopRunning()
        var count = 0
        for await (audio, when) in stream {
            let pcm = try #require(audio as? AVAudioPCMBuffer)
            #expect(pcm.frameLength > 500)
            #expect(when.sampleTime == 0)
            #expect((0..<Int(pcm.frameLength)).contains { abs(pcm.floatChannelData![0][$0]) > 0.1 })
            count += 1
        }
        #expect(count == 1)
    }

    @Test func convertsOpusToRequestedPCMSampleRate() async throws {
        let codec = AudioCodec()
        codec.settings = .init(sampleRate: 24_000, format: .pcm)
        let stream = codec.outputStream
        codec.startRunning()
        for (index, packet) in try encode(channels: 1).enumerated() {
            codec.append(try buffer(packet, channels: 1), when: AVAudioTime(sampleTime: Int64(index * 960), atRate: 48_000))
        }
        codec.stopRunning()
        var frames = 0
        for await (audio, when) in stream {
            let pcm = try #require(audio as? AVAudioPCMBuffer)
            #expect(pcm.format.sampleRate == 24_000)
            #expect(when.sampleRate == 24_000)
            frames += Int(pcm.frameLength)
        }
        #expect(frames >= 480 * 7)
    }

    private func decode(_ packets: [Data], channels: Int, framesPerPacket: UInt32 = 0,
                        preSkip: UInt16 = 0, outputGain: Int16 = 0, gap: Bool = false) async throws -> [(AVAudioPCMBuffer, AVAudioTime)] {
        let codec = AudioCodec()
        codec.settings.format = .pcm
        let stream = codec.outputStream
        codec.startRunning()
        if preSkip != 0 || outputGain != 0 { codec.configureOpusDecoder(preSkip: preSkip, outputGain: outputGain) }
        for (index, data) in packets.enumerated() {
            let position = Int64(63_360_000 + index * 960 + (gap && index >= 4 ? 48_000 : 0))
            codec.append(try buffer(data, channels: channels, framesPerPacket: framesPerPacket),
                when: AVAudioTime(sampleTime: position, atRate: 48_000))
        }
        codec.stopRunning()
        var output: [(AVAudioPCMBuffer, AVAudioTime)] = []
        for await (audio, when) in stream { output.append((try #require(audio as? AVAudioPCMBuffer), when)) }
        return output
    }

    private func buffer(_ data: Data, channels: Int, framesPerPacket: UInt32 = 0) throws -> AVAudioCompressedBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatOpus,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: framesPerPacket, mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        let format = try #require(AVAudioFormat(streamDescription: &description))
        let buffer = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: max(1, data.count))
        buffer.byteLength = UInt32(data.count)
        buffer.packetCount = 1
        buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0,
            mVariableFramesInPacket: 960, mDataByteSize: buffer.byteLength)
        data.copyBytes(to: buffer.data.assumingMemoryBound(to: UInt8.self), count: data.count)
        return buffer
    }

    private func encode(channels: Int) throws -> [Data] {
        let pcm = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: UInt32(channels)))
        let format = try buffer(Data(), channels: channels, framesPerPacket: 960).format
        let encoder = try #require(AVAudioConverter(from: pcm, to: format))
        var packets: [Data] = []
        for packet in 0..<8 {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 960))
            input.frameLength = 960
            for channel in 0..<channels {
                for index in 0..<960 { input.floatChannelData![channel][index] = Float(sin(Double(packet * 960 + index) * 0.05)) * 0.3 }
            }
            let output = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: 4000)
            var supplied = false
            var error: NSError?
            _ = encoder.convert(to: output, error: &error) { _, state in
                guard !supplied else { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return input
            }
            try #require(error == nil)
            if output.byteLength > 0 { packets.append(Data(bytes: output.data, count: Int(output.byteLength))) }
        }
        return packets
    }
}
