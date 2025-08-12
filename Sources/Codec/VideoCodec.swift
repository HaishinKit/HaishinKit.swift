import AVFoundation
import CoreFoundation
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

/**
 * The interface a VideoCodec uses to inform its delegate.
 */
protocol VideoCodecDelegate: AnyObject {
    /// Tells the receiver to set a formatDescription.
    func videoCodec(_ codec: VideoCodec<Self>, didOutput formatDescription: CMFormatDescription?)
    /// Tells the receiver to output an encoded or decoded sampleBuffer.
    func videoCodec(_ codec: VideoCodec<Self>, didOutput sampleBuffer: CMSampleBuffer)
    /// Tells the receiver to occured an error.
    func videoCodec(_ codec: VideoCodec<Self>, errorOccurred error: IOVideoUnitError)
}

private let kVideoCodec_defaultFrameInterval: Double = 0.0

// MARK: -
/**
 * The VideoCodec class provides methods for encode or decode for video.
 */
final class VideoCodec<T: VideoCodecDelegate> {
    let lockQueue: DispatchQueue

    /// Specifies the settings for a VideoCodec.
    var settings: VideoCodecSettings = .default {
        didSet {
            let invalidateSession = settings.invalidateSession(oldValue)
            if invalidateSession {
                self.invalidateSession = invalidateSession
            } else {
                settings.apply(self, rhs: oldValue)
            }
        }
    }

    /// The running value indicating whether the VideoCodec is running.
    private(set) var isRunning: Atomic<Bool> = .init(false)
    var needsSync: Atomic<Bool> = .init(true)
    var passthrough = true
    var frameInterval = kVideoCodec_defaultFrameInterval
    var expectedFrameRate = IOMixer.defaultFrameRate
    weak var delegate: T?
    private var startedAt: CMTime = .zero
    private(set) var inputFormat: CMFormatDescription? {
        didSet {
            guard inputFormat != oldValue else {
                return
            }
            invalidateSession = true
            outputFormat = nil
        }
    }
    private(set) var outputFormat: CMFormatDescription? {
        didSet {
            guard outputFormat != oldValue else {
                return
            }
            delegate?.videoCodec(self, didOutput: outputFormat)
        }
    }
    private(set) var session: (any VTSessionConvertible)? {
        didSet {
            oldValue?.invalidate()
            invalidateSession = false
        }
    }
    private var invalidateSession = true
    private var presentationTimeStamp: CMTime = .zero

    init(lockQueue: DispatchQueue) {
        self.lockQueue = lockQueue
    }

    func append(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard isRunning.value, useFrame(presentationTimeStamp) else {
            return
        }
        if invalidateSession {
            session = VTSessionMode.compression.makeSession(self)
        }
        _ = session?.encodeFrame(
            imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration
        ) { [unowned self] status, _, sampleBuffer in
            guard let sampleBuffer, status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            self.presentationTimeStamp = sampleBuffer.presentationTimeStamp
            outputFormat = sampleBuffer.formatDescription
            delegate?.videoCodec(self, didOutput: sampleBuffer)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        inputFormat = sampleBuffer.formatDescription
        guard isRunning.value else {
            return
        }
        if invalidateSession {
            session = VTSessionMode.decompression.makeSession(self)
            needsSync.mutate { $0 = true }
        }
        if !sampleBuffer.isNotSync {
            needsSync.mutate { $0 = false }
        }
        _ = session?.decodeFrame(sampleBuffer) { [unowned self] status, _, imageBuffer, presentationTimeStamp, duration in
            guard let imageBuffer, status == noErr else {
                self.delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            var status = noErr
            if outputFormat == nil {
                status = CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: imageBuffer,
                    formatDescriptionOut: &outputFormat
                )
            }
            guard let outputFormat, status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            var timingInfo = CMSampleTimingInfo(
                duration: duration,
                presentationTimeStamp: presentationTimeStamp,
                decodeTimeStamp: sampleBuffer.decodeTimeStamp
            )
            var sampleBuffer: CMSampleBuffer?
            status = CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: outputFormat,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            guard let buffer = sampleBuffer, status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            delegate?.videoCodec(self, didOutput: buffer)
        }
    }

    func imageBufferAttributes(_ mode: VTSessionMode) -> [NSString: AnyObject]? {
        switch mode {
        case .compression:
            var attributes: [NSString: AnyObject] = [:]
            if let inputFormat {
                // Specify the pixel format of the uncompressed video.
                attributes[kCVPixelBufferPixelFormatTypeKey] = inputFormat.mediaType.rawValue as CFNumber
            }
            return attributes.isEmpty ? nil : attributes
        case .decompression:
            return [
                kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
                kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
            ]
        }
    }

    private func useFrame(_ presentationTimeStamp: CMTime) -> Bool {
        guard startedAt <= presentationTimeStamp else {
            return false
        }
        guard self.presentationTimeStamp < presentationTimeStamp else {
            return false
        }
        guard kVideoCodec_defaultFrameInterval < frameInterval else {
            return true
        }
        return frameInterval <= presentationTimeStamp.seconds - self.presentationTimeStamp.seconds
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    @objc
    private func applicationWillEnterForeground(_ notification: Notification) {
        invalidateSession = true
    }

    @objc
    private func didAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo: [AnyHashable: Any] = notification.userInfo,
            let value: NSNumber = userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber,
            let type = AVAudioSession.InterruptionType(rawValue: value.uintValue) else {
            return
        }
        switch type {
        case .ended:
            invalidateSession = true
        default:
            break
        }
    }
    #endif
}

extension VideoCodec: Running {
    // MARK: Running
    func startRunning() {
        lockQueue.async {
            #if os(iOS) || os(tvOS) || os(visionOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.didAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.applicationWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            #endif
            self.startedAt = self.passthrough ? .zero : CMClockGetTime(CMClockGetHostTimeClock())
            self.isRunning.mutate { $0 = true }
        }
    }

    func stopRunning() {
        lockQueue.async {
            self.isRunning.mutate { $0 = false }
            self.session = nil
            self.invalidateSession = true
            self.needsSync.mutate { $0 = true }
            self.inputFormat = nil
            self.outputFormat = nil
            self.presentationTimeStamp = .zero
            self.startedAt = .zero
            #if os(iOS) || os(tvOS) || os(visionOS)
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
            #endif
        }
    }
}
