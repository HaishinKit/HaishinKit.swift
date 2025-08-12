import AudioUnit
import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

final class IOAudioMonitor {
    var inputFormat: AVAudioFormat? {
        didSet {
            if let inputFormat {
                ringBuffer = .init(inputFormat)
                if isRunning.value {
                    audioUnit = makeAudioUnit()
                }
            } else {
                ringBuffer = nil
            }
        }
    }
    private(set) var isRunning: Atomic<Bool> = .init(false)
    private var audioUnit: AudioUnit? {
        didSet {
            if let oldValue {
                AudioOutputUnitStop(oldValue)
                AudioUnitUninitialize(oldValue)
                AudioComponentInstanceDispose(oldValue)
            }
            if let audioUnit {
                AudioOutputUnitStart(audioUnit)
            }
        }
    }
    private var ringBuffer: IOAudioRingBuffer?

    private let callback: AURenderCallback = { (inRefCon: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _: UnsafePointer<AudioTimeStamp>, _: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) in
        let monitor = Unmanaged<IOAudioMonitor>.fromOpaque(inRefCon).takeUnretainedValue()
        return monitor.render(inNumberFrames, ioData: ioData)
    }

    deinit {
        stopRunning()
    }

    func append(_ audioPCMBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard isRunning.value else {
            return
        }
        ringBuffer?.append(audioPCMBuffer, when: when)
    }

    private func render(_ inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ringBuffer else {
            return noErr
        }
        if ringBuffer.counts == 0 {
            guard let bufferList = UnsafeMutableAudioBufferListPointer(ioData) else {
                return noErr
            }
            for i in 0..<bufferList.count {
                memset(bufferList[i].mData, 0, Int(bufferList[i].mDataByteSize))
            }
            return noErr
        }
        return ringBuffer.render(inNumberFrames, ioData: ioData)
    }

    private func makeAudioUnit() -> AudioUnit? {
        guard let inputFormat else {
            return nil
        }
        var inSourceFormat = inputFormat.formatDescription.audioStreamBasicDescription
        var audioUnit: AudioUnit?
        #if os(macOS)
        let subType = kAudioUnitSubType_DefaultOutput
        #else
        let subType = kAudioUnitSubType_RemoteIO
        #endif
        var audioComponentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        let audioComponent = AudioComponentFindNext(nil, &audioComponentDescription)
        if let audioComponent {
            AudioComponentInstanceNew(audioComponent, &audioUnit)
        }
        if let audioUnit {
            AudioUnitInitialize(audioUnit)
            let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            var callbackstruct = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: ref)
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackstruct, UInt32(MemoryLayout.size(ofValue: callbackstruct)))
            AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &inSourceFormat, UInt32(MemoryLayout.size(ofValue: inSourceFormat)))
        }
        return audioUnit
    }
}

extension IOAudioMonitor: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        audioUnit = makeAudioUnit()
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        audioUnit = nil
        isRunning.mutate { $0 = false }
    }
}
