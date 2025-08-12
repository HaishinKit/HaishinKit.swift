import AVFoundation

#if canImport(SwiftPMSupport)
import SwiftPMSupport
#endif

protocol IOMixerDelegate: AnyObject {
    func mixer(_ mixer: IOMixer, track: UInt8, didInput audio: AVAudioBuffer, when: AVAudioTime)
    func mixer(_ mixer: IOMixer, track: UInt8, didInput video: CMSampleBuffer)
    func mixer(_ mixer: IOMixer, didOutput audio: AVAudioPCMBuffer, when: AVAudioTime)
    func mixer(_ mixer: IOMixer, didOutput video: CMSampleBuffer)
    func mixer(_ mixer: IOMixer, videoErrorOccurred error: IOVideoUnitError)
    func mixer(_ mixer: IOMixer, audioErrorOccurred error: IOAudioUnitError)
    #if os(iOS) || os(tvOS) || os(visionOS)
    @available(tvOS 17.0, *)
    func mixer(_ mixer: IOMixer, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?)
    @available(tvOS 17.0, *)
    func mixer(_ mixer: IOMixer, sessionInterruptionEnded session: AVCaptureSession)
    #endif
    #if os(iOS) || os(tvOS)
    @available(tvOS 17.0, *)
    func mixer(_ mixer: IOMixer, mediaServicesWereReset error: AVError)
    #endif
}

/// An object that mixies audio and video for streaming.
final class IOMixer {
    static let defaultFrameRate: Float64 = 30

    weak var muxer: (any IOMuxer)?

    weak var delegate: (any IOMixerDelegate)?

    private(set) var isRunning: Atomic<Bool> = .init(false)

    private(set) lazy var audioIO = {
        var audioIO = IOAudioUnit()
        audioIO.mixer = self
        return audioIO
    }()

    private(set) lazy var videoIO = {
        var videoIO = IOVideoUnit()
        videoIO.mixer = self
        return videoIO
    }()

    private(set) lazy var session = {
        var session = IOCaptureSession()
        session.delegate = self
        return session
    }()

    private(set) lazy var audioEngine: AVAudioEngine? = {
        return IOStream.audioEngineHolder.retain()
    }()

    deinit {
        IOStream.audioEngineHolder.release(audioEngine)
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    func setBackgroundMode(_ background: Bool) {
        guard #available(tvOS 17.0, *) else {
            return
        }
        if background {
            videoIO.setBackgroundMode(background)
        } else {
            videoIO.setBackgroundMode(background)
            session.startRunningIfNeeded()
        }
    }
    #endif
}

extension IOMixer: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        muxer?.startRunning()
        audioIO.startRunning()
        videoIO.startRunning()
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        videoIO.stopRunning()
        audioIO.stopRunning()
        muxer?.stopRunning()
        isRunning.mutate { $0 = false }
    }
}

extension IOMixer: VideoCodecDelegate {
    // MARK: VideoCodecDelegate
    func videoCodec(_ codec: VideoCodec<IOMixer>, didOutput formatDescription: CMFormatDescription?) {
        muxer?.videoFormat = formatDescription
    }

    func videoCodec(_ codec: VideoCodec<IOMixer>, didOutput sampleBuffer: CMSampleBuffer) {
        if sampleBuffer.formatDescription?.isCompressed == false {
            delegate?.mixer(self, didOutput: sampleBuffer)
        }
        muxer?.append(sampleBuffer)
    }

    func videoCodec(_ codec: VideoCodec<IOMixer>, errorOccurred error: IOVideoUnitError) {
        delegate?.mixer(self, videoErrorOccurred: error)
    }
}

extension IOMixer: AudioCodecDelegate {
    // MARK: AudioCodecDelegate
    func audioCodec(_ codec: AudioCodec<IOMixer>, didOutput audioFormat: AVAudioFormat?) {
        muxer?.audioFormat = audioFormat
    }

    func audioCodec(_ codec: AudioCodec<IOMixer>, didOutput audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        switch audioBuffer {
        case let audioBuffer as AVAudioPCMBuffer:
            delegate?.mixer(self, didOutput: audioBuffer, when: when)
        default:
            break
        }
        muxer?.append(audioBuffer, when: when)
        codec.releaseOutputBuffer(audioBuffer)
    }

    func audioCodec(_ codec: AudioCodec<IOMixer>, errorOccurred error: IOAudioUnitError) {
        delegate?.mixer(self, audioErrorOccurred: error)
    }
}

extension IOMixer: IOCaptureSessionDelegate {
    // MARK: IOCaptureSessionDelegate
    @available(tvOS 17.0, *)
    func captureSession(_ capture: IOCaptureSession, sessionRuntimeError session: AVCaptureSession, error: AVError) {
        #if os(iOS) || os(tvOS) || os(macOS)
        switch error.code {
        case .unsupportedDeviceActiveFormat:
            guard let device = error.device, let format = device.videoFormat(
                width: session.sessionPreset.width ?? Int32(videoIO.settings.videoSize.width),
                height: session.sessionPreset.height ?? Int32(videoIO.settings.videoSize.height),
                frameRate: videoIO.frameRate,
                isMultiCamSupported: capture.isMultiCamSessionEnabled
            ), device.activeFormat != format else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                if format.isFrameRateSupported(videoIO.frameRate) {
                    device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * videoIO.frameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * videoIO.frameRate))
                }
                device.unlockForConfiguration()
                capture.startRunningIfNeeded()
            } catch {
                logger.warn(error)
            }
        default:
            break
        }
        #endif
        switch error.code {
        #if os(iOS) || os(tvOS)
        case .mediaServicesWereReset:
            delegate?.mixer(self, mediaServicesWereReset: error)
        #endif
        default:
            break
        }
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    @available(tvOS 17.0, *)
    func captureSession(_ _: IOCaptureSession, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?) {
        delegate?.mixer(self, sessionWasInterrupted: session, reason: reason)
    }

    @available(tvOS 17.0, *)
    func captureSession(_ _: IOCaptureSession, sessionInterruptionEnded session: AVCaptureSession) {
        delegate?.mixer(self, sessionInterruptionEnded: session)
    }
    #endif
}

extension IOMixer: IOAudioUnitDelegate {
    // MARK: IOAudioUnitDelegate
    func audioUnit(_ audioUnit: IOAudioUnit, track: UInt8, didInput audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        delegate?.mixer(self, track: track, didInput: audioBuffer, when: when)
    }

    func audioUnit(_ audioUnit: IOAudioUnit, errorOccurred error: IOAudioUnitError) {
        delegate?.mixer(self, audioErrorOccurred: error)
    }

    func audioUnit(_ audioUnit: IOAudioUnit, didOutput audioBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        delegate?.mixer(self, didOutput: audioBuffer, when: when)
    }
}

extension IOMixer: IOVideoUnitDelegate {
    // MARK: IOVideoUnitDelegate
    func videoUnit(_ videoUnit: IOVideoUnit, track: UInt8, didInput sampleBuffer: CMSampleBuffer) {
        delegate?.mixer(self, track: track, didInput: sampleBuffer)
    }

    func videoUnit(_ videoUnit: IOVideoUnit, didOutput sampleBuffer: CMSampleBuffer) {
        delegate?.mixer(self, didOutput: sampleBuffer)
    }
}
