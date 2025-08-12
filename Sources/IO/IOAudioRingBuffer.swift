import Accelerate
import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

final class IOAudioRingBuffer {
    private static let bufferCounts: UInt32 = 16
    private static let numSamples: UInt32 = 1024

    var counts: Int {
        if tail <= head {
            return head - tail + skip
        }
        return Int(outputBuffer.frameLength) - tail + head + skip
    }

    private var head = 0
    private var tail = 0
    private var skip = 0
    private var sampleTime: AVAudioFramePosition = 0
    private var inputFormat: AVAudioFormat
    private var inputBuffer: AVAudioPCMBuffer
    private var outputBuffer: AVAudioPCMBuffer

    init?(_ inputFormat: AVAudioFormat, bufferCounts: UInt32 = IOAudioRingBuffer.bufferCounts) {
        guard
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.numSamples) else {
            return nil
        }
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.numSamples * bufferCounts) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.inputBuffer = inputBuffer
        self.outputBuffer = outputBuffer
        self.outputBuffer.frameLength = self.outputBuffer.frameCapacity
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        let targetSampleTime: CMTimeValue
        if sampleBuffer.presentationTimeStamp.timescale == Int32(inputBuffer.format.sampleRate) {
            targetSampleTime = sampleBuffer.presentationTimeStamp.value
        } else {
            targetSampleTime = Int64(Double(sampleBuffer.presentationTimeStamp.value) * inputBuffer.format.sampleRate / Double(sampleBuffer.presentationTimeStamp.timescale))
        }
        if sampleTime == 0 {
            sampleTime = targetSampleTime
        }
        if inputBuffer.frameLength < sampleBuffer.numSamples {
            if let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) {
                self.inputBuffer = buffer
            }
        }
        inputBuffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleBuffer.numSamples),
            into: inputBuffer.mutableAudioBufferList
        )
        if status == noErr && kLinearPCMFormatFlagIsBigEndian == ((sampleBuffer.formatDescription?.audioStreamBasicDescription?.mFormatFlags ?? 0) & kLinearPCMFormatFlagIsBigEndian) {
            if inputFormat.isInterleaved {
                switch inputFormat.commonFormat {
                case .pcmFormatInt16:
                    let length = sampleBuffer.dataBuffer?.dataLength ?? 0
                    var image = vImage_Buffer(data: inputBuffer.mutableAudioBufferList[0].mBuffers.mData, height: 1, width: vImagePixelCount(length / 2), rowBytes: length)
                    vImageByteSwap_Planar16U(&image, &image, vImage_Flags(kvImageNoFlags))
                default:
                    break
                }
            }
        }
        skip = max(Int(targetSampleTime - sampleTime), 0)
        sampleTime += Int64(skip)
        append(inputBuffer)
    }

    func append(_ audioPCMBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        if sampleTime == 0 {
            sampleTime = when.sampleTime
        }
        if inputBuffer.frameLength < audioPCMBuffer.frameLength {
            if let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: audioPCMBuffer.frameCapacity) {
                self.inputBuffer = buffer
            }
        }
        inputBuffer.frameLength = audioPCMBuffer.frameLength
        _ = inputBuffer.copy(audioPCMBuffer)
        skip = Int(max(when.sampleTime - sampleTime, 0))
        sampleTime += Int64(skip)
        append(inputBuffer)
    }

    @inline(__always)
    private func append(_ audioPCMBuffer: AVAudioPCMBuffer, offset: Int = 0) {
        let numSamples = min(Int(audioPCMBuffer.frameLength) - offset, Int(outputBuffer.frameLength) - head)
        if inputFormat.isInterleaved {
            let channelCount = Int(inputFormat.channelCount)
            switch inputFormat.commonFormat {
            case .pcmFormatInt16:
                memcpy(outputBuffer.int16ChannelData?[0].advanced(by: head * channelCount), audioPCMBuffer.int16ChannelData?[0].advanced(by: offset * channelCount), numSamples * channelCount * 2)
            case .pcmFormatInt32:
                memcpy(outputBuffer.int32ChannelData?[0].advanced(by: head * channelCount), audioPCMBuffer.int32ChannelData?[0].advanced(by: offset * channelCount), numSamples * channelCount * 4)
            case .pcmFormatFloat32:
                memcpy(outputBuffer.floatChannelData?[0].advanced(by: head * channelCount), audioPCMBuffer.floatChannelData?[0].advanced(by: offset * channelCount), numSamples * channelCount * 4)
            default:
                break
            }
        } else {
            for i in 0..<Int(inputFormat.channelCount) {
                switch inputFormat.commonFormat {
                case .pcmFormatInt16:
                    memcpy(outputBuffer.int16ChannelData?[i].advanced(by: head), audioPCMBuffer.int16ChannelData?[i].advanced(by: offset), numSamples * 2)
                case .pcmFormatInt32:
                    memcpy(outputBuffer.int32ChannelData?[i].advanced(by: head), audioPCMBuffer.int32ChannelData?[i].advanced(by: offset), numSamples * 4)
                case .pcmFormatFloat32:
                    memcpy(outputBuffer.floatChannelData?[i].advanced(by: head), audioPCMBuffer.floatChannelData?[i].advanced(by: offset), numSamples * 4)
                default:
                    break
                }
            }
        }
        head += numSamples
        sampleTime += Int64(numSamples)
        if head == outputBuffer.frameLength {
            head = 0
            if 0 < Int(audioPCMBuffer.frameLength) - numSamples {
                append(audioPCMBuffer, offset: numSamples)
            }
        }
    }

    func render(_ inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?, offset: Int = 0) -> OSStatus {
        if 0 < skip {
            let numSamples = min(Int(inNumberFrames), skip)
            guard let bufferList = UnsafeMutableAudioBufferListPointer(ioData) else {
                return noErr
            }
            if inputFormat.isInterleaved {
                let channelCount = Int(inputFormat.channelCount)
                switch inputFormat.commonFormat {
                case .pcmFormatInt16:
                    bufferList[0].mData?.assumingMemoryBound(to: Int16.self).advanced(by: offset * channelCount).update(repeating: 0, count: numSamples)
                case .pcmFormatInt32:
                    bufferList[0].mData?.assumingMemoryBound(to: Int32.self).advanced(by: offset * channelCount).update(repeating: 0, count: numSamples)
                case .pcmFormatFloat32:
                    bufferList[0].mData?.assumingMemoryBound(to: Float32.self).advanced(by: offset * channelCount).update(repeating: 0, count: numSamples)
                default:
                    break
                }
            } else {
                for i in 0..<Int(inputFormat.channelCount) {
                    switch inputFormat.commonFormat {
                    case .pcmFormatInt16:
                        bufferList[i].mData?.assumingMemoryBound(to: Int16.self).advanced(by: offset).update(repeating: 0, count: numSamples)
                    case .pcmFormatInt32:
                        bufferList[i].mData?.assumingMemoryBound(to: Int32.self).advanced(by: offset).update(repeating: 0, count: numSamples)
                    case .pcmFormatFloat32:
                        bufferList[i].mData?.assumingMemoryBound(to: Float32.self).advanced(by: offset).update(repeating: 0, count: numSamples)
                    default:
                        break
                    }
                }
            }
            skip -= numSamples
            if 0 < inNumberFrames - UInt32(numSamples) {
                return render(inNumberFrames - UInt32(numSamples), ioData: ioData, offset: numSamples)
            }
            return noErr
        }
        let numSamples = min(Int(inNumberFrames), Int(outputBuffer.frameLength) - tail)
        guard let bufferList = UnsafeMutableAudioBufferListPointer(ioData), head != tail else {
            return noErr
        }
        if inputFormat.isInterleaved {
            let channelCount = Int(inputFormat.channelCount)
            switch inputFormat.commonFormat {
            case .pcmFormatInt16:
                memcpy(bufferList[0].mData?.advanced(by: offset * channelCount * 2), outputBuffer.int16ChannelData?[0].advanced(by: tail * channelCount), numSamples * channelCount * 2)
            case .pcmFormatInt32:
                memcpy(bufferList[0].mData?.advanced(by: offset * channelCount * 4), outputBuffer.int32ChannelData?[0].advanced(by: tail * channelCount), numSamples * channelCount * 4)
            case .pcmFormatFloat32:
                memcpy(bufferList[0].mData?.advanced(by: offset * channelCount * 4), outputBuffer.floatChannelData?[0].advanced(by: tail * channelCount), numSamples * channelCount * 4)
            default:
                break
            }
        } else {
            for i in 0..<Int(inputFormat.channelCount) {
                switch inputFormat.commonFormat {
                case .pcmFormatInt16:
                    memcpy(bufferList[i].mData?.advanced(by: offset * 2), outputBuffer.int16ChannelData?[i].advanced(by: tail), numSamples * 2)
                case .pcmFormatInt32:
                    memcpy(bufferList[i].mData?.advanced(by: offset * 4), outputBuffer.int32ChannelData?[i].advanced(by: tail), numSamples * 4)
                case .pcmFormatFloat32:
                    memcpy(bufferList[i].mData?.advanced(by: offset * 4), outputBuffer.floatChannelData?[i].advanced(by: tail), numSamples * 4)
                default:
                    break
                }
            }
        }
        tail += numSamples
        if tail == outputBuffer.frameLength {
            tail = 0
            if 0 < inNumberFrames - UInt32(numSamples) {
                return render(inNumberFrames - UInt32(numSamples), ioData: ioData, offset: numSamples)
            }
        }
        return noErr
    }
}
