import AVFoundation

final class AudioCaptureUnit: CaptureUnit {
    let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.AudioCaptureUnit.lock")
    var mixerSettings: AudioMixerSettings {
        get {
            audioMixer.settings
        }
        set {
            audioMixer.settings = newValue
        }
    }
    var isMonitoringEnabled = false {
        didSet {
            if isMonitoringEnabled {
                monitor.startRunning()
            } else {
                monitor.stopRunning()
            }
        }
    }
    var isMultiTrackAudioMixingEnabled = false
    var inputFormats: [UInt8: AVAudioFormat] {
        return audioMixer.inputFormats
    }
    var output: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)> {
        AsyncStream<(AVAudioPCMBuffer, AVAudioTime)> { continutation in
            self.continutation = continutation
        }
    }
    private(set) var isSuspended = false
    private lazy var audioMixer: any AudioMixer = {
        if isMultiTrackAudioMixingEnabled {
            var mixer = AudioMixerByMultiTrack()
            mixer.delegate = self
            return mixer
        } else {
            var mixer = AudioMixerBySingleTrack()
            mixer.delegate = self
            return mixer
        }
    }()
    private var monitor: AudioMonitor = .init()

    #if os(tvOS)
    private var _devices: [UInt8: Any] = [:]
    @available(tvOS 17.0, *)
    var devices: [UInt8: AudioDeviceUnit] {
        set {
            _devices = newValue
        }
        get {
            _devices as! [UInt8: AudioDeviceUnit]
        }
    }
    #else
    var devices: [UInt8: AudioDeviceUnit] = [:]
    #endif

    private let session: (any CaptureSessionConvertible)
    private var continutation: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.Continuation?

    init(_ session: (some CaptureSessionConvertible), isMultiTrackAudioMixingEnabled: Bool) {
        self.session = session
        self.isMultiTrackAudioMixingEnabled = isMultiTrackAudioMixingEnabled
    }

    #if os(iOS) || os(macOS) || os(tvOS)
    @available(tvOS 17.0, *)
    func attachAudio(_ track: UInt8, device: AVCaptureDevice?, configuration: AudioDeviceConfigurationBlock?) throws {
        try session.configuration { _ in
            session.detachCapture(devices[track])
            devices[track] = nil
            if let device {
                let capture = try AudioDeviceUnit(track, device: device)
                capture.setSampleBufferDelegate(self)
                try? configuration?(capture)
                session.attachCapture(capture)
                devices[track] = capture
            }
        }
    }

    @available(tvOS 17.0, *)
    func makeDataOutput(_ track: UInt8) -> AudioDeviceUnitDataOutput {
        return .init(track: track, audioMixer: audioMixer)
    }
    #endif

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        audioMixer.append(track, buffer: buffer)
    }

    func append(_ track: UInt8, buffer: AVAudioBuffer, when: AVAudioTime) {
        switch buffer {
        case let buffer as AVAudioPCMBuffer:
            audioMixer.append(track, buffer: buffer, when: when)
        default:
            break
        }
    }

    @available(tvOS 17.0, *)
    func suspend() {
        guard !isSuspended else {
            return
        }
        for capture in devices.values {
            session.detachCapture(capture)
        }
        isSuspended = true
    }

    @available(tvOS 17.0, *)
    func resume() {
        guard isSuspended else {
            return
        }
        for capture in devices.values {
            session.attachCapture(capture)
        }
        isSuspended = false
    }

    func finish() {
        continutation?.finish()
    }
}

extension AudioCaptureUnit: AudioMixerDelegate {
    // MARK: AudioMixerDelegate
    func audioMixer(_ audioMixer: some AudioMixer, track: UInt8, didInput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
    }

    func audioMixer(_ audioMixer: some AudioMixer, errorOccurred error: AudioMixerError) {
    }

    func audioMixer(_ audioMixer: some AudioMixer, didOutput audioFormat: AVAudioFormat) {
        monitor.inputFormat = audioFormat
    }

    func audioMixer(_ audioMixer: some AudioMixer, didOutput audioBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        if let audioBuffer = audioBuffer.clone() {
            continutation?.yield((audioBuffer, when))
        }
        monitor.append(audioBuffer, when: when)
    }
}
