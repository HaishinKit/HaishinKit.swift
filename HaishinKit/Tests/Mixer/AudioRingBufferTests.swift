import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct AudioRingBufferTests {
    @Test func monoAppendSampleBuffer_920() throws {
        try appendSampleBuffer(920, channels: 1)
    }

    @Test func monoAppendSampleBuffer_1024() throws {
        try appendSampleBuffer(1024, channels: 1)
    }

    @Test func stereoAppendSampleBuffer_920() throws {
        try appendSampleBuffer(920, channels: 2)
    }

    @Test func stereoAppendSampleBuffer_1024() throws {
        try appendSampleBuffer(1024, channels: 2)
    }

    @Test func reusesInputBufferWhenCapacityIsSufficient() throws {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!
        let ringBuffer = AudioRingBuffer(audioFormat, bufferCounts: 3)!
        let initialInternalPCMBuff = ringBuffer.testableInputBuffer
        let buffer1 = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 1)!
        buffer1.frameLength = 1
        ringBuffer.append(buffer1, when: .init(sampleTime: 0, atRate: 48000))

        #expect(initialInternalPCMBuff === ringBuffer.testableInputBuffer)
    }

    @Test func reallocatesInputBufferWhenCapacityIsInsufficient() throws {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!
        let ringBuffer = AudioRingBuffer(audioFormat, bufferCounts: 3)!
        let initialInternalPCMBuff = ringBuffer.testableInputBuffer
        let buffer1 = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: initialInternalPCMBuff.frameCapacity + 1)!
        buffer1.frameLength = buffer1.frameCapacity
        ringBuffer.append(buffer1, when: .init(sampleTime: 0, atRate: 48000))

        #expect(initialInternalPCMBuff !== ringBuffer.testableInputBuffer)
        #expect(ringBuffer.testableInputBuffer.frameCapacity == buffer1.frameCapacity)
    }

    private func appendSampleBuffer(_ numSamples: Int, channels: UInt32) throws {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: 0xc,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        let format = AVAudioFormat(streamDescription: &asbd)
        let buffer = AudioRingBuffer(format!, bufferCounts: 3)
        guard
            let readBuffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(streamDescription: &asbd)!, frameCapacity: AVAudioFrameCount(numSamples)),
            let sinWave = CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: numSamples, channels: channels) else {
            return
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(readBuffer.mutableAudioBufferList)
        readBuffer.frameLength = AVAudioFrameCount(numSamples)
        for _ in 0..<30 {
            buffer?.append(sinWave)
            readBuffer.int16ChannelData?[0].update(repeating: 0, count: numSamples)
            _ = buffer?.render(UInt32(numSamples), ioData: readBuffer.mutableAudioBufferList)
            #expect(try sinWave.dataBuffer?.dataBytes().bytes == Data(bytes: bufferList[0].mData!, count: numSamples * Int(channels) * 2).bytes)
        }
    }
}
