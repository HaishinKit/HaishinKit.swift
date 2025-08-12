import AVFoundation
import CoreImage

/// The IOVideoUnit error domain codes.
public enum IOVideoUnitError: Error {
    /// The IOVideoUnit failed to attach device.
    case failedToAttach(error: (any Error)?)
    /// The IOVideoUnit failed to create the VTSession.
    case failedToCreate(status: OSStatus)
    /// The IOVideoUnit  failed to prepare the VTSession.
    case failedToPrepare(status: OSStatus)
    /// The IOVideoUnit failed to encode or decode a flame.
    case failedToFlame(status: OSStatus)
    /// The IOVideoUnit failed to set an option.
    case failedToSetOption(status: OSStatus, option: VTSessionOption)
}

protocol IOVideoUnitDelegate: AnyObject {
    func videoUnit(_ videoUnit: IOVideoUnit, track: UInt8, didInput sampleBuffer: CMSampleBuffer)
    func videoUnit(_ videoUnit: IOVideoUnit, didOutput sampleBuffer: CMSampleBuffer)
}

final class IOVideoUnit: IOUnit {
    enum Error: Swift.Error {
        case multiCamNotSupported
    }

    let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.IOVideoUnit.lock")
    weak var mixer: IOMixer?

    weak var view: (any IOStreamView)? {
        didSet {
            #if os(iOS) || os(macOS)
            view?.videoOrientation = videoOrientation
            #endif
        }
    }

    var screen: Screen {
        return videoMixer.screen
    }

    var mixerSettings: IOVideoMixerSettings {
        get {
            return videoMixer.settings
        }
        set {
            videoMixer.settings = newValue
        }
    }
    var settings: VideoCodecSettings {
        get {
            return codec.settings
        }
        set {
            codec.settings = newValue
        }
    }
    var inputFormats: [UInt8: CMFormatDescription] {
        return videoMixer.inputFormats
    }
    var outputFormat: CMFormatDescription? {
        codec.outputFormat
    }
    var frameRate = IOMixer.defaultFrameRate {
        didSet {
            guard #available(tvOS 17.0, *) else {
                return
            }
            for capture in captures.values {
                capture.setFrameRate(frameRate)
            }
        }
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    var torch = false {
        didSet {
            guard #available(tvOS 17.0, *), torch != oldValue else {
                return
            }
            setTorchMode(torch ? .on : .off)
        }
    }
    #endif

    @available(tvOS 17.0, *)
    var hasDevice: Bool {
        !captures.lazy.filter { $0.value.device != nil }.isEmpty
    }

    var isRunning: Atomic<Bool> {
        return codec.isRunning
    }

    #if os(iOS) || os(macOS)
    var videoOrientation: AVCaptureVideoOrientation = .portrait {
        didSet {
            guard videoOrientation != oldValue else {
                return
            }
            mixer?.session.configuration { _ in
                view?.videoOrientation = videoOrientation
                for capture in captures.values {
                    capture.videoOrientation = videoOrientation
                }
            }
            // https://github.com/shogo4405/HaishinKit.swift/issues/190
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.torch {
                    self.setTorchMode(.on)
                }
            }
        }
    }
    #endif

    private lazy var videoMixer = {
        var videoMixer = IOVideoMixer<IOVideoUnit>()
        videoMixer.delegate = self
        return videoMixer
    }()

    private lazy var codec = {
        var codec = VideoCodec<IOMixer>(lockQueue: lockQueue)
        codec.delegate = mixer
        return codec
    }()

    #if os(tvOS)
    private var _captures: [UInt8: Any] = [:]
    @available(tvOS 17.0, *)
    var captures: [UInt8: IOVideoCaptureUnit] {
        return _captures as! [UInt8: IOVideoCaptureUnit]
    }
    #elseif os(iOS) || os(macOS) || os(visionOS)
    var captures: [UInt8: IOVideoCaptureUnit] = [:]
    #endif

    deinit {
        if Thread.isMainThread {
            self.view?.attachStream(nil)
        } else {
            DispatchQueue.main.sync {
                self.view?.attachStream(nil)
            }
        }
    }

    func registerEffect(_ effect: VideoEffect) -> Bool {
        return videoMixer.registerEffect(effect)
    }

    func unregisterEffect(_ effect: VideoEffect) -> Bool {
        return videoMixer.unregisterEffect(effect)
    }

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        if buffer.formatDescription?.isCompressed == true {
            codec.append(buffer)
        } else {
            videoMixer.append(track, sampleBuffer: buffer)
        }
    }

    @available(tvOS 17.0, *)
    func attachCamera(_ device: AVCaptureDevice?, track: UInt8, configuration: IOVideoCaptureConfigurationBlock?) throws {
        guard captures[track]?.device != device else {
            return
        }
        if hasDevice && device != nil && captures[track]?.device == nil && mixer?.session.isMultiCamSessionEnabled == false {
            throw Error.multiCamNotSupported
        }
        try mixer?.session.configuration { _ in
            for capture in captures.values where capture.device == device {
                try? capture.attachDevice(nil, videoUnit: self)
            }
            let capture = self.capture(for: track)
            configuration?(capture, nil)
            videoMixer.reset(track)
            try capture?.attachDevice(device, videoUnit: self)
        }
        if device != nil && view != nil {
            // Start captureing if not running.
            mixer?.session.startRunning()
        }
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    @available(tvOS 17.0, *)
    func setTorchMode(_ torchMode: AVCaptureDevice.TorchMode) {
        for capture in captures.values {
            capture.setTorchMode(torchMode)
        }
    }
    #endif

    @available(tvOS 17.0, *)
    func setBackgroundMode(_ background: Bool) {
        guard let session = mixer?.session, !session.isMultitaskingCameraAccessEnabled else {
            return
        }
        if background {
            for capture in captures.values {
                mixer?.session.detachCapture(capture)
            }
        } else {
            for capture in captures.values {
                mixer?.session.attachCapture(capture)
            }
        }
    }

    @available(tvOS 17.0, *)
    func makeDataOutput(_ track: UInt8) -> IOVideoCaptureUnitDataOutput {
        return .init(track: track, videoMixer: videoMixer)
    }

    @available(tvOS 17.0, *)
    func capture(for track: UInt8) -> IOVideoCaptureUnit? {
        #if os(tvOS)
        if _captures[track] == nil {
            _captures[track] = .init(track)
        }
        return _captures[track] as? IOVideoCaptureUnit
        #else
        if captures[track] == nil {
            captures[track] = .init(track)
        }
        return captures[track]
        #endif
    }
}

extension IOVideoUnit: Running {
    // MARK: Running
    func startRunning() {
        #if os(iOS)
        if let capture = captures.values.first {
            codec.passthrough = capture.preferredVideoStabilizationMode == .off
        }
        #endif
        codec.startRunning()
    }

    func stopRunning() {
        codec.stopRunning()
    }
}

extension IOVideoUnit: IOVideoMixerDelegate {
    // MARK: IOVideoMixerDelegate
    func videoMixer(_ videoMixer: IOVideoMixer<IOVideoUnit>, track: UInt8, didInput sampleBuffer: CMSampleBuffer) {
        mixer?.videoUnit(self, track: track, didInput: sampleBuffer)
    }

    func videoMixer(_ videoMixer: IOVideoMixer<IOVideoUnit>, didOutput sampleBuffer: CMSampleBuffer) {
        if let imageBuffer = sampleBuffer.imageBuffer {
            codec.append(
                imageBuffer,
                presentationTimeStamp: sampleBuffer.presentationTimeStamp,
                duration: sampleBuffer.duration
            )
        }
        view?.enqueue(sampleBuffer)
        mixer?.videoUnit(self, didOutput: sampleBuffer)
    }
}
