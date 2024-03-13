import AVFoundation

private let kIOAudioMixer_frameCapacity: AVAudioFrameCount = 1024
private let kIOAudioMixer_sampleTime: AVAudioFramePosition = 0
private let kIOAudioMixer_defaultResamplerTag: Int = 0

/// The IOAudioMixerError  error domain codes.
public enum IOAudioMixerError: Swift.Error {
    /// Invalid resample settings.
    case invalidSampleRate
    /// Mixer is unable to make sure that all resamplers output the same audio format.
    case unableToEnforceAudioFormat
}

protocol IOAudioMixerDelegate: AnyObject {
    func audioMixer(_ audioMixer: IOAudioMixer, didOutput audioFormat: AVAudioFormat)
    func audioMixer(_ audioMixer: IOAudioMixer, didOutput audioBuffer: AVAudioPCMBuffer, when: AVAudioTime)
    func audioMixer(_ audioMixer: IOAudioMixer, errorOccurred error: IOAudioUnitError)
}

struct IOAudioMixerSettings {
    let defaultResamplerSettings: IOAudioResamplerSettings
    let resamplersSettings: [Int: IOAudioResamplerSettings]

    init(defaultResamplerSettings: IOAudioResamplerSettings) {
        self.defaultResamplerSettings = defaultResamplerSettings
        self.resamplersSettings = [
            kIOAudioMixer_defaultResamplerTag: defaultResamplerSettings
        ]
    }

    init(resamplersSettings: [Int: IOAudioResamplerSettings] = [:]) {
        let defaultSettings = resamplersSettings[kIOAudioMixer_defaultResamplerTag] ?? .init()
        self.defaultResamplerSettings = defaultSettings
        self.resamplersSettings = resamplersSettings.merging([kIOAudioMixer_defaultResamplerTag: defaultSettings]) { _, settings in
            settings
        }
    }

    func resamplerSettings(channel: Int, sampleRate: Float64, channels: UInt32) -> IOAudioResamplerSettings {
        let preferredSettings = resamplersSettings[channel] ?? .init()
        return .init(
            sampleRate: sampleRate,
            channels: channels,
            downmix: preferredSettings.downmix,
            channelMap: preferredSettings.channelMap
        )
    }
}

final class IOAudioMixer {
    private class Track {
        let resampler: IOAudioResampler<IOAudioMixer>
        var ringBuffer: IOAudioRingBuffer?

        init(resampler: IOAudioResampler<IOAudioMixer>, format: AVAudioFormat? = nil) {
            self.resampler = resampler
            if let format {
                self.ringBuffer = .init(format)
            }
        }
    }

    var delegate: (any IOAudioMixerDelegate)?
    var settings: IOAudioMixerSettings = .init() {
        didSet {
            defaultTrack.resampler.settings = settings.defaultResamplerSettings
            if !settings.defaultResamplerSettings.invalidate(oldValue.defaultResamplerSettings) {
                enforceResamplersSettings()
            }
        }
    }
    var inputFormat: AVAudioFormat? {
        return defaultTrack.resampler.inputFormat
    }
    var outputFormat: AVAudioFormat? {
        return defaultTrack.resampler.outputFormat
    }
    private(set) var numberOfTracks = 0
    private var tracks: [Int: Track] = [:] {
        didSet {
            numberOfTracks += 1
            tryToSetupAudioNodes()
        }
    }
    private var shouldMix: Bool {
        numberOfTracks > 1
    }
    private var anchor: AVAudioTime?
    private var sampleTime: AVAudioFramePosition = kIOAudioMixer_sampleTime
    private var mixerNode: MixerNode?
    private var outputNode: OutputNode?
    private lazy var defaultTrack: Track = {
        createTrack(channel: kIOAudioMixer_defaultResamplerTag, settings: settings.defaultResamplerSettings)
    }()

    private let inputRenderCallback: AURenderCallback = { (inRefCon: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) in
        let audioMixer = Unmanaged<IOAudioMixer>.fromOpaque(inRefCon).takeUnretainedValue()
        let status = audioMixer.provideInput(inNumberFrames, channel: Int(inBusNumber), ioData: ioData)
        guard status == noErr else {
            fatalError()
        }
        return status
    }

    func append(_ sampleBuffer: CMSampleBuffer, channel: UInt8 = 0) {
        if sampleTime == kIOAudioMixer_sampleTime, channel == kIOAudioMixer_defaultResamplerTag {
            sampleTime = sampleBuffer.presentationTimeStamp.value
            if let outputFormat {
                anchor = .init(hostTime: AVAudioTime.hostTime(forSeconds: sampleBuffer.presentationTimeStamp.seconds), sampleTime: sampleTime, atRate: outputFormat.sampleRate)
            }
        }
        track(channel: Int(channel))?.resampler.append(sampleBuffer)
    }

    func append(_ audioBuffer: AVAudioPCMBuffer, channel: UInt8, when: AVAudioTime) {
        if sampleTime == kIOAudioMixer_sampleTime, channel == kIOAudioMixer_defaultResamplerTag {
            sampleTime = when.sampleTime
            anchor = when
        }
        track(channel: Int(channel))?.resampler.append(audioBuffer, when: when)
    }

    private func createTrack(channel: Int, settings: IOAudioResamplerSettings) -> Track {
        let resampler = IOAudioResampler<IOAudioMixer>()
        resampler.tag = channel
        resampler.settings = settings
        resampler.delegate = self
        let track = Track(resampler: resampler)
        tracks[channel] = track
        return track
    }

    private func track(channel: Int) -> Track? {
        if channel == kIOAudioMixer_defaultResamplerTag {
            return defaultTrack
        } else if let track = tracks[channel] {
            return track
        } else if let sampleRate = outputFormat?.sampleRate, let channels = outputFormat?.channelCount {
            if tracks[kIOAudioMixer_defaultResamplerTag] == nil {
                _ = createTrack(channel: kIOAudioMixer_defaultResamplerTag, settings: settings.defaultResamplerSettings)
            }
            return createTrack(channel: channel,
                               settings: settings.resamplerSettings(channel: channel, sampleRate: sampleRate, channels: channels))
        }
        return nil
    }

    private func tryToSetupAudioNodes() {
        guard shouldMix else {
            return
        }
        do {
            try setupAudioNodes()
        } catch {
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: error))
        }
    }

    private func setupAudioNodes() throws {
        mixerNode = nil
        outputNode = nil
        guard let outputFormat else {
            return
        }
        sampleTime = kIOAudioMixer_sampleTime
        let mixerNode = try MixerNode(format: outputFormat)
        try mixerNode.update(busCount: numberOfTracks, scope: .input)
        let busCount = try mixerNode.busCount(scope: .input)
        if busCount > numberOfTracks {
            for index in numberOfTracks..<busCount {
                try mixerNode.enable(bus: index, scope: .input, isEnabled: false)
            }
        }
        for (bus, _) in tracks {
            try mixerNode.update(format: outputFormat, bus: bus, scope: .input)

            var callbackStruct = AURenderCallbackStruct(inputProc: inputRenderCallback,
                                                        inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try mixerNode.update(inputCallback: &callbackStruct, bus: bus)
            try mixerNode.update(volume: 1, bus: bus, scope: .input)
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

    private func provideInput(_ inNumberFrames: UInt32, channel: Int, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ringBuffer = track(channel: channel)?.ringBuffer else {
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
        let status = ringBuffer.render(inNumberFrames, ioData: ioData)
        return status
    }

    private func mix(numberOfFrames: AVAudioFrameCount) {
        guard let outputNode else {
            return
        }
        do {
            let buffer = try outputNode.render(numberOfFrames: numberOfFrames, sampleTime: sampleTime)
            let time = AVAudioTime(sampleTime: sampleTime, atRate: outputNode.format.sampleRate)
            if let anchor, let when = time.extrapolateTime(fromAnchor: anchor) {
                delegate?.audioMixer(self, didOutput: buffer, when: when)
                sampleTime += Int64(numberOfFrames)
            }
        } catch {
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: error))
        }
    }

    private func enforceResamplersSettings() {
        guard shouldMix else {
            return
        }
        guard let outputFormat else {
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: IOAudioMixerError.unableToEnforceAudioFormat))
            return
        }
        for (channel, track) in tracks {
            if channel == kIOAudioMixer_defaultResamplerTag {
                continue
            }
            let preferredSettings = settings.resamplersSettings[channel] ?? .init()
            track.resampler.settings = IOAudioResamplerSettings(
                sampleRate: outputFormat.sampleRate,
                channels: outputFormat.channelCount,
                downmix: preferredSettings.downmix,
                channelMap: preferredSettings.channelMap
            )
        }
    }
}

extension IOAudioMixer: IOAudioResamplerDelegate {
    // MARK: IOAudioResamplerDelegate
    func resampler(_ resampler: IOAudioResampler<IOAudioMixer>, didOutput audioFormat: AVAudioFormat) {
        guard shouldMix else {
            if resampler.tag == kIOAudioMixer_defaultResamplerTag {
                delegate?.audioMixer(self, didOutput: audioFormat)
            }
            return
        }
        if resampler.tag == kIOAudioMixer_defaultResamplerTag {
            enforceResamplersSettings()
            tryToSetupAudioNodes()
            delegate?.audioMixer(self, didOutput: audioFormat)
        }
        track(channel: resampler.tag)?.ringBuffer = .init(audioFormat)
    }

    func resampler(_ resampler: IOAudioResampler<IOAudioMixer>, didOutput audioBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard shouldMix else {
            if resampler.tag == kIOAudioMixer_defaultResamplerTag {
                delegate?.audioMixer(self, didOutput: audioBuffer, when: when)
            }
            return
        }
        guard audioBuffer.format.sampleRate == outputFormat?.sampleRate else {
            delegate?.audioMixer(self, errorOccurred: .failedToMix(error: IOAudioMixerError.invalidSampleRate))
            return
        }
        guard let track = track(channel: resampler.tag) else {
            return
        }
        track.ringBuffer?.append(audioBuffer, when: when)

        if resampler.tag == kIOAudioMixer_defaultResamplerTag {
            mix(numberOfFrames: audioBuffer.frameLength)
        }
    }

    func resampler(_ resampler: IOAudioResampler<IOAudioMixer>, errorOccurred error: IOAudioUnitError) {
        delegate?.audioMixer(self, errorOccurred: error)
    }
}
