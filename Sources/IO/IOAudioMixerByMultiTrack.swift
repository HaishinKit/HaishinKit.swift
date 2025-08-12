import AVFoundation
import CoreAudio
import Foundation

final class IOAudioMixerByMultiTrack: IOAudioMixerConvertible {
    private static let defaultSampleTime: AVAudioFramePosition = 0

    weak var delegate: (any IOAudioMixerDelegate)?
    var settings = IOAudioMixerSettings.default {
        didSet {
            if let inSourceFormat, settings.invalidateOutputFormat(oldValue) {
                outputFormat = settings.makeOutputFormat(inSourceFormat)
            }
            for (id, trackSettings) in settings.tracks {
                tracks[id]?.settings = trackSettings
                try? mixerNode?.update(volume: trackSettings.volume, bus: id, scope: .input)
            }
        }
    }
    var inputFormats: [UInt8: AVAudioFormat] {
        return tracks.compactMapValues { $0.inputFormat }
    }
    private(set) var outputFormat: AVAudioFormat? {
        didSet {
            guard let outputFormat, outputFormat != oldValue else {
                return
            }
            for id in tracks.keys {
                buffers[id] = .init(outputFormat)
                tracks[id] = .init(id: id, outputFormat: outputFormat)
                tracks[id]?.delegate = self
            }
        }
    }
    private var inSourceFormat: CMFormatDescription? {
        didSet {
            guard inSourceFormat != oldValue else {
                return
            }
            outputFormat = settings.makeOutputFormat(inSourceFormat)
        }
    }
    private var tracks: [UInt8: IOAudioMixerTrack<IOAudioMixerByMultiTrack>] = [:] {
        didSet {
            tryToSetupAudioNodes()
        }
    }
    private var anchor: AVAudioTime?
    private var buffers: [UInt8: IOAudioRingBuffer] = [:] {
        didSet {
            if logger.isEnabledFor(level: .trace) {
                logger.trace(buffers)
            }
        }
    }
    private var mixerNode: MixerNode?
    private var sampleTime: AVAudioFramePosition = IOAudioMixerByMultiTrack.defaultSampleTime
    private var outputNode: OutputNode?

    private let inputRenderCallback: AURenderCallback = { (inRefCon: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) in
        let audioMixer = Unmanaged<IOAudioMixerByMultiTrack>.fromOpaque(inRefCon).takeUnretainedValue()
        let status = audioMixer.render(UInt8(inBusNumber), inNumberFrames: inNumberFrames, ioData: ioData)
        guard status == noErr else {
            audioMixer.delegate?.audioMixer(audioMixer, errorOccurred: .failedToMix(error: IOAudioMixerError.unableToProvideInputData))
            return noErr
        }
        return status
    }

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        if settings.mainTrack == track {
            inSourceFormat = buffer.formatDescription
        }
        self.track(for: track)?.append(buffer)
    }

    func append(_ track: UInt8, buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        if settings.mainTrack == track {
            inSourceFormat = buffer.format.formatDescription
        }
        self.track(for: track)?.append(buffer, when: when)
    }

    private func tryToSetupAudioNodes() {
        do {
            try setupAudioNodes()
        } catch {
            logger.error(error)
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: error))
        }
    }

    private func setupAudioNodes() throws {
        mixerNode = nil
        outputNode = nil
        guard let outputFormat else {
            return
        }
        sampleTime = Self.defaultSampleTime
        let mixerNode = try MixerNode(format: outputFormat)
        try mixerNode.update(busCount: tracks.count, scope: .input)
        let busCount = try mixerNode.busCount(scope: .input)
        for index in 0..<busCount {
            try mixerNode.enable(bus: UInt8(index), scope: .input, isEnabled: false)
        }
        for (bus, track) in tracks {
            try mixerNode.enable(bus: bus, scope: .input, isEnabled: true)
            try mixerNode.update(format: outputFormat, bus: bus, scope: .input)
            var callbackStruct = AURenderCallbackStruct(inputProc: inputRenderCallback,
                                                        inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try mixerNode.update(inputCallback: &callbackStruct, bus: bus)
            try mixerNode.update(volume: track.settings.volume, bus: bus, scope: .input)
        }
        try mixerNode.update(format: outputFormat, bus: 0, scope: .output)
        try mixerNode.update(volume: 1, bus: 0, scope: .output)
        let outputNode = try OutputNode(format: outputFormat)
        try outputNode.update(format: outputFormat, bus: 0, scope: .input)
        try outputNode.update(format: outputFormat, bus: 0, scope: .output)
        try mixerNode.connect(to: outputNode)
        try mixerNode.initializeAudioUnit()
        try outputNode.initializeAudioUnit()
        self.mixerNode = mixerNode
        self.outputNode = outputNode
        if logger.isEnabledFor(level: .info) {
            logger.info("mixerAudioUnit: \(mixerNode)")
        }
    }

    private func render(_ track: UInt8, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let buffer = buffers[track] else {
            return noErr
        }
        if buffer.counts == 0 {
            guard let bufferList = UnsafeMutableAudioBufferListPointer(ioData) else {
                return noErr
            }
            for i in 0..<bufferList.count {
                memset(bufferList[i].mData, 0, Int(bufferList[i].mDataByteSize))
            }
            return noErr
        }
        return buffer.render(inNumberFrames, ioData: ioData)
    }

    private func mix(numberOfFrames: AVAudioFrameCount) {
        guard let outputNode else {
            return
        }
        do {
            let buffer = try outputNode.render(numberOfFrames: numberOfFrames, sampleTime: sampleTime)
            let time = AVAudioTime(sampleTime: sampleTime, atRate: outputNode.format.sampleRate)
            if let anchor, let when = time.extrapolateTime(fromAnchor: anchor) {
                delegate?.audioMixer(self, didOutput: buffer.muted(settings.isMuted), when: when)
                sampleTime += Int64(numberOfFrames)
            }
        } catch {
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: error))
        }
    }

    private func track(for id: UInt8) -> IOAudioMixerTrack<IOAudioMixerByMultiTrack>? {
        if let track = tracks[id] {
            return track
        }
        guard let outputFormat else {
            return nil
        }
        let track = IOAudioMixerTrack<IOAudioMixerByMultiTrack>(id: id, outputFormat: outputFormat)
        track.delegate = self
        if let trackSettings = settings.tracks[id] {
            track.settings = trackSettings
        }
        tracks[id] = track
        buffers[id] = .init(outputFormat)
        return track
    }
}

extension IOAudioMixerByMultiTrack: IOAudioMixerTrackDelegate {
    // MARK: IOAudioMixerTrackDelegate
    func track(_ track: IOAudioMixerTrack<IOAudioMixerByMultiTrack>, didOutput audioPCMBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        delegate?.audioMixer(self, track: track.id, didInput: audioPCMBuffer, when: when)
        buffers[track.id]?.append(audioPCMBuffer, when: when)
        if settings.mainTrack == track.id {
            if sampleTime == Self.defaultSampleTime {
                sampleTime = when.sampleTime
                anchor = when
            }
            mix(numberOfFrames: audioPCMBuffer.frameLength)
        }
    }

    func track(_ track: IOAudioMixerTrack<IOAudioMixerByMultiTrack>, errorOccurred error: IOAudioUnitError) {
        delegate?.audioMixer(self, errorOccurred: error)
    }
}
