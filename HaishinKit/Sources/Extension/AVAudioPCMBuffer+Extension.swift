import Accelerate
import AVFoundation

public extension AVAudioPCMBuffer {
    final func makeSampleBuffer(_ when: AVAudioTime) -> CMSampleBuffer? {
        var status: OSStatus = noErr
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: nil,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: Int(frameLength),
            presentationTimeStamp: when.makeTime(),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else {
            logger.warn("CMAudioSampleBufferCreateWithPacketDescriptions returned error: ", status)
            return nil
        }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )
        if status != noErr {
            logger.warn("CMSampleBufferSetDataBufferFromAudioBufferList returned error: ", status)
        }
        return sampleBuffer
    }

    @discardableResult
    @inlinable
    final func copy(_ audioBuffer: AVAudioBuffer) -> Bool {
        guard let audioBuffer = audioBuffer as? AVAudioPCMBuffer, frameLength == audioBuffer.frameLength else {
            return false
        }
        let numSamples = Int(frameLength)
        if format.isInterleaved {
            let channelCount = Int(format.channelCount)
            switch format.commonFormat {
            case .pcmFormatInt16:
                memcpy(int16ChannelData?[0], audioBuffer.int16ChannelData?[0], numSamples * channelCount * 2)
            case .pcmFormatInt32:
                memcpy(int32ChannelData?[0], audioBuffer.int32ChannelData?[0], numSamples * channelCount * 4)
            case .pcmFormatFloat32:
                memcpy(floatChannelData?[0], audioBuffer.floatChannelData?[0], numSamples * channelCount * 4)
            default:
                break
            }
        } else {
            for i in 0..<Int(format.channelCount) {
                switch format.commonFormat {
                case .pcmFormatInt16:
                    memcpy(int16ChannelData?[i], audioBuffer.int16ChannelData?[i], numSamples * 2)
                case .pcmFormatInt32:
                    memcpy(int32ChannelData?[i], audioBuffer.int32ChannelData?[i], numSamples * 4)
                case .pcmFormatFloat32:
                    memcpy(floatChannelData?[i], audioBuffer.floatChannelData?[i], numSamples * 4)
                default:
                    break
                }
            }
        }
        return true
    }

    final func clone() -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        buffer.frameLength = frameLength
        buffer.copy(self)
        return buffer
    }

    @discardableResult
    @inlinable
    final func muted(_ isMuted: Bool) -> AVAudioPCMBuffer {
        guard isMuted else {
            return self
        }
        let numSamples = Int(frameLength)
        if format.isInterleaved {
            let channelCount = Int(format.channelCount)
            switch format.commonFormat {
            case .pcmFormatInt16:
                int16ChannelData?[0].update(repeating: 0, count: numSamples * channelCount)
            case .pcmFormatInt32:
                int32ChannelData?[0].update(repeating: 0, count: numSamples * channelCount)
            case .pcmFormatFloat32:
                floatChannelData?[0].update(repeating: 0, count: numSamples * channelCount)
            default:
                break
            }
        } else {
            for i in 0..<Int(format.channelCount) {
                switch format.commonFormat {
                case .pcmFormatInt16:
                    int16ChannelData?[i].update(repeating: 0, count: numSamples)
                case .pcmFormatInt32:
                    int32ChannelData?[i].update(repeating: 0, count: numSamples)
                case .pcmFormatFloat32:
                    floatChannelData?[i].update(repeating: 0, count: numSamples)
                default:
                    break
                }
            }
        }
        return self
    }
}
