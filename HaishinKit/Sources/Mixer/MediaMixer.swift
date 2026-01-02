@preconcurrency import AVFoundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

/// An actor that mixies audio and video for streaming.
public final actor MediaMixer {
    static let defaultFrameRate: Float64 = 30

    /// The error domain codes.
    public enum Error: Swift.Error {
        /// The mixer failed to failed to attach device.
        case failedToAttach(_ error: any Swift.Error)
        /// The mixer missing a device of track.
        case deviceNotFound
    }

    /// An enumeration defines the capture session mode used for video/audio input.
    public enum CaptureSessionMode: Sendable {
        /// Uses a standard `AVCaptureSession`
        case single
        /// Uses an `AVCaptureMultiCamSession`
        case multi
        /// Does not use a `AVCaptureSession`. Set this when using ReplayKit, as AVCaptureSession is not required.
        case manual

        func makeSession() -> (any CaptureSessionConvertible) {
            switch self {
            case .single:
                let session = CaptureSession()
                session.isMultiCamSessionEnabled = false
                return session
            case .multi:
                let session = CaptureSession()
                session.isMultiCamSessionEnabled = true
                return session
            case .manual:
                return NullCaptureSession()
            }
        }
    }

    /// The offscreen rendering object.
    @ScreenActor
    public private(set) lazy var screen = Screen()

    /// The capture session mode.
    public let captureSessionMode: CaptureSessionMode

    /// The feature to mix multiple audio tracks. For example, it is possible to mix .appAudio and .micAudio from ReplayKit.
    public let isMultiTrackAudioMixingEnabled: Bool

    /// The dynamic range mode.
    public private(set) var dynamicRangeMode: DynamicRangeMode = .sdr

    #if os(iOS) || os(tvOS)
    /// The AVCaptureMultiCamSession enabled.
    @available(tvOS 17.0, *)
    public var isMultiCamSessionEnabled: Bool {
        session.isMultiCamSessionEnabled
    }
    #endif

    #if os(iOS) || os(macOS) || os(tvOS)
    /// The device torch indicating wheter the turn on(TRUE) or not(FALSE).
    public var isTorchEnabled: Bool {
        videoIO.isTorchEnabled
    }

    /// The sessionPreset for the AVCaptureSession.
    @available(tvOS 17.0, *)
    public var sessionPreset: AVCaptureSession.Preset {
        session.sessionPreset
    }
    #endif

    /// The audio monitoring enabled or not.
    public var isMonitoringEnabled: Bool {
        audioIO.isMonitoringEnabled
    }

    /// The audio mixer settings.
    public var audioMixerSettings: AudioMixerSettings {
        audioIO.mixerSettings
    }

    /// The video mixer settings.
    public var videoMixerSettings: VideoMixerSettings {
        videoIO.mixerSettings
    }

    /// The audio input formats.
    public var audioInputFormats: [UInt8: AVAudioFormat] {
        audioIO.inputFormats
    }

    /// The video input formats.
    public var videoInputFormats: [UInt8: CMFormatDescription] {
        videoIO.inputFormats
    }

    /// The output frame rate.
    public private(set) var frameRate = MediaMixer.defaultFrameRate

    /// The AVCaptureSession is in a running state or not.
    @available(tvOS 17.0, *)
    public var isCapturing: Bool {
        session.isCapturing
    }

    /// The interrupts events is occured or not.
    public var isInterputted: AsyncStream<Bool> {
        session.isInturreped
    }

    #if os(iOS) || os(macOS)
    /// The video orientation for stream.
    public var videoOrientation: AVCaptureVideoOrientation {
        videoIO.videoOrientation
    }
    #endif

    public private(set) var isRunning = false
    private var outputs: [any MediaMixerOutput] = []
    @MainActor
    private var cancellables: Set<AnyCancellable> = []
    private var subscriptions: [Task<Void, Never>] = []
    private var isInBackground = false
    private lazy var audioIO = AudioCaptureUnit(session, isMultiTrackAudioMixingEnabled: isMultiTrackAudioMixingEnabled)
    private lazy var videoIO = VideoCaptureUnit(session)
    private lazy var session: (any CaptureSessionConvertible) = captureSessionMode.makeSession()
    @ScreenActor
    private lazy var displayLink = DisplayLinkChoreographer()

    /// Creates a new instance.
    ///
    /// - Parameters:
    ///   - captureSessionMode: Specifies the capture session mode.
    ///   - multiTrackAudioMixingEnabled: Specifies the feature to mix multiple audio tracks. For example, it is possible to mix .appAudio and .micAudio from ReplayKit.
    public init(
        captureSessionMode: CaptureSessionMode = .single,
        multiTrackAudioMixingEnabled: Bool = false
    ) {
        self.captureSessionMode = captureSessionMode
        self.isMultiTrackAudioMixingEnabled = multiTrackAudioMixingEnabled
    }

    /// Attaches a video device.
    ///
    /// If you want to use the multi-camera feature, please make create a MediaMixer with a multiCamSession mode for iOS.
    /// ```swift
    /// let mixer = MediaMixer(captureSessionMode: .multi)
    /// ```
    @available(tvOS 17.0, *)
    public func attachVideo(_ device: AVCaptureDevice?, track: UInt8 = 0, configuration: VideoDeviceConfigurationBlock? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try videoIO.attachVideo(track, device: device, configuration: configuration)
                continuation.resume()
            } catch {
                continuation.resume(throwing: Error.failedToAttach(error))
            }
        }
    }

    /// Configurations for a video device.
    @available(tvOS 17.0, *)
    public func configuration(video track: UInt8, configuration: VideoDeviceConfigurationBlock) throws {
        guard let unit = videoIO.devices[track] else {
            throw Error.deviceNotFound
        }
        try configuration(unit)
    }

    #if os(iOS) || os(macOS) || os(tvOS)
    /// Attaches an audio device.
    ///
    /// - Attention: You can perform multi-microphone capture by specifying as follows on macOS. Unfortunately, it seems that only one microphone is available on iOS.
    ///
    /// ```swift
    /// let mixer = MediaMixer(multiTrackAudioMixingEnabled: true)
    ///
    /// var audios = AVCaptureDevice.devices(for: .audio)
    /// if let device = audios.removeFirst() {
    ///    mixer.attachAudio(device, track: 0)
    /// }
    /// if let device = audios.removeFirst() {
    ///    mixer.attachAudio(device, track: 1)
    /// }
    /// ```
    @available(tvOS 17.0, *)
    public func attachAudio(_ device: AVCaptureDevice?, track: UInt8 = 0, configuration: AudioDeviceConfigurationBlock? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try audioIO.attachAudio(track, device: device, configuration: configuration)
                continuation.resume()
            } catch {
                continuation.resume(throwing: Error.failedToAttach(error))
            }
        }
    }

    /// Configurations for an audio device.
    @available(tvOS 17.0, *)
    public func configuration(audio track: UInt8, configuration: AudioDeviceConfigurationBlock) throws {
        guard let unit = audioIO.devices[track] else {
            throw Error.deviceNotFound
        }
        try configuration(unit)
    }

    /// Sets the device torch indicating wheter the turn on(TRUE) or not(FALSE).
    public func setTorchEnabled(_ torchEnabled: Bool) {
        videoIO.isTorchEnabled = torchEnabled
    }

    /// Sets the sessionPreset for the AVCaptureSession.
    @available(tvOS 17.0, *)
    public func setSessionPreset(_ sessionPreset: AVCaptureSession.Preset) {
        session.sessionPreset = sessionPreset
    }
    #endif

    #if os(iOS) || os(macOS)
    /// Sets the video orientation for stream.
    public func setVideoOrientation(_ videoOrientation: AVCaptureVideoOrientation) {
        videoIO.videoOrientation = videoOrientation
        // https://github.com/shogo4405/HaishinKit.swift/issues/190
        if videoIO.isTorchEnabled {
            videoIO.isTorchEnabled = true
        }
    }
    #endif

    /// Appends a CMSampleBuffer.
    /// - Parameters:
    ///   - sampleBuffer:The sample buffer to append.
    ///   - track: Track number used for mixing
    public func append(_ sampleBuffer: CMSampleBuffer, track: UInt8 = 0) {
        switch sampleBuffer.formatDescription?.mediaType {
        case .audio?:
            audioIO.append(track, buffer: sampleBuffer)
        case .video?:
            videoIO.append(track, buffer: sampleBuffer)
        default:
            break
        }
    }

    /// Sets the video mixier settings.
    public func setVideoMixerSettings(_ settings: VideoMixerSettings) {
        let mode = self.videoMixerSettings.mode
        if mode != settings.mode {
            setVideoRenderingMode(settings.mode)
        }
        videoIO.mixerSettings = settings
        Task { @ScreenActor in
            screen.videoTrackScreenObject.track = settings.mainTrack
        }
    }

    /// Sets the output frame rate of the mixer.
    ///
    /// This is distinct from the camera capture rate, which can be configured separately as shown below.
    /// ```swift
    /// try? await mixer.configuration(video: 0) { video in
    ///     try? video.setFrameRate(fps)
    /// }
    /// ```
    public func setFrameRate(_ frameRate: Float64) throws {
        switch videoMixerSettings.mode {
        case .passthrough:
            if #available(tvOS 17.0, *) {
                try videoIO.devices.first?.value.setFrameRate(frameRate)
            }
        case .offscreen:
            Task { @ScreenActor in
                displayLink.preferredFramesPerSecond = Int(frameRate)
            }
        }
        self.frameRate = frameRate
    }

    /// Sets the dynamic range mode.
    ///
    /// Warnings: It takes some time for changes to be applied to the camera device, so it’s better not to modify it dynamically during a live stream.
    public func setDynamicRangeMode(_ dynamicRangeMode: DynamicRangeMode) throws {
        guard self.dynamicRangeMode != dynamicRangeMode else {
            return
        }
        Task { @ScreenActor in
            screen.dynamicRangeMode = dynamicRangeMode
        }
        videoIO.dynamicRangeMode = dynamicRangeMode
        self.dynamicRangeMode = dynamicRangeMode
    }

    /// Sets the audio mixer settings.
    public func setAudioMixerSettings(_ settings: AudioMixerSettings) {
        audioIO.mixerSettings = settings
    }

    /// Sets the audio monitoring enabled or not.
    public func setMonitoringEnabled(_ monitoringEnabled: Bool) {
        audioIO.isMonitoringEnabled = monitoringEnabled
    }

    /// Starts capturing from input devices.
    ///
    /// Internally, it is called either when the view is attached or just before publishing. In other cases, please call this method if you want to manually start the capture.
    @available(tvOS 17.0, *)
    public func startCapturing() {
        guard !session.isRunning else {
            session.startRunningIfNeeded()
            return
        }
        session.startRunning()
        let synchronizationClock = session.synchronizationClock
        Task { @ScreenActor in
            screen.synchronizationClock = synchronizationClock
        }
        Task {
            for await runtimeError in session.runtimeError {
                await sessionRuntimeErrorOccured(runtimeError)
            }
        }
    }

    /// Stops capturing from input devices.
    @available(tvOS 17.0, *)
    public func stopCapturing() {
        guard session.isRunning else {
            return
        }
        session.stopRunning()
        Task { @ScreenActor in
            screen.synchronizationClock = nil
        }
    }

    /// Appends an AVAudioBuffer.
    /// - Parameters:
    ///   - audioBuffer:The audio buffer to append.
    ///   - when: The audio time to append.
    ///   - track: Track number used for mixing.
    public func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime, track: UInt8 = 0) {
        audioIO.append(track, buffer: audioBuffer, when: when)
    }

    /// Configurations for the AVCaptureSession.
    /// - Attention: Internally, there is no need for developers to call beginConfiguration() and func commitConfiguration() as they are called automatically.
    @available(tvOS 17.0, *)
    public func configuration(_ lambda: @Sendable (_ session: AVCaptureSession) throws -> Void) rethrows {
        try session.configuration(lambda)
    }

    /// Adds an output observer.
    public func addOutput(_ output: some MediaMixerOutput) {
        guard !outputs.contains(where: { $0 === output }) else {
            return
        }
        outputs.append(output)
    }

    /// Removes an output observer.
    public func removeOutput(_ output: some MediaMixerOutput) {
        if let index = outputs.firstIndex(where: { $0 === output }) {
            outputs.remove(at: index)
        }
    }

    private func setVideoRenderingMode(_ mode: VideoMixerSettings.Mode) {
        guard isRunning else {
            return
        }
        switch mode {
        case .passthrough:
            Task { @ScreenActor in
                displayLink.stopRunning()
            }
        case .offscreen:
            Task { @ScreenActor in
                displayLink.preferredFramesPerSecond = await Int(frameRate)
                displayLink.startRunning()
                for await updateFrame in displayLink.updateFrames {
                    guard let buffer = screen.makeSampleBuffer(updateFrame) else {
                        continue
                    }
                    for output in await self.outputs where await output.videoTrackId == UInt8.max {
                        output.mixer(self, didOutput: buffer)
                    }
                }
            }
        }
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    private func setInBackground(_ isInBackground: Bool) {
        self.isInBackground = isInBackground
        guard #available(tvOS 17.0, *) else {
            return
        }
        if isInBackground {
            videoIO.setBackgroundMode(isInBackground)
        } else {
            videoIO.setBackgroundMode(isInBackground)
            session.startRunningIfNeeded()
        }
    }

    @available(tvOS 17.0, *)
    private func didAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            // video capture continues even while an incoming call is ringing.
            audioIO.suspend()
            session.startRunningIfNeeded()
            logger.info("Audio suspended due to system interruption.")
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) {
                audioIO.resume()
            }
            logger.info("Audio resumed after system interruption")
        default: ()
        }
    }
    #endif

    @available(tvOS 17.0, *)
    private func sessionRuntimeErrorOccured(_ error: AVError) async {
        switch error.code {
        #if os(iOS) || os(tvOS) || os(visionOS)
        case .mediaServicesWereReset:
            session.startRunningIfNeeded()
        #endif
        #if os(iOS) || os(tvOS) || os(macOS)
        case .unsupportedDeviceActiveFormat:
            guard let device = error.device, let format = device.videoFormat(
                width: session.sessionPreset.width ?? Int32.max,
                height: session.sessionPreset.height ?? Int32.max,
                frameRate: frameRate,
                isMultiCamSupported: session.isMultiCamSessionEnabled
            ), device.activeFormat != format else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                if format.isFrameRateSupported(frameRate) {
                    device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                }
                device.unlockForConfiguration()
                session.startRunningIfNeeded()
            } catch {
                logger.warn(error)
            }
        #endif
        case .unknown:
            // AVFoundationErrorDomain Code=-11800 "The operation could not be completed"
            if error.errorCode == -11800 && !isInBackground {
                session.startRunningIfNeeded()
            }
        default:
            break
        }
    }
}

extension MediaMixer: AsyncRunner {
    // MARK: AsyncRunner
    public func startRunning() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        setVideoRenderingMode(videoMixerSettings.mode)
        if #available(tvOS 17.0, *) {
            startCapturing()
        }
        Task {
            for await inputs in videoIO.inputs {
                Task { @ScreenActor in
                    let videoMixerSettings = await self.videoMixerSettings
                    guard videoMixerSettings.mode == .offscreen else {
                        return
                    }
                    let sampleBuffer = inputs.1
                    screen.append(inputs.0, buffer: sampleBuffer)
                    if videoMixerSettings.mainTrack == inputs.0 {
                        screen.setVideoCaptureLatency(sampleBuffer.presentationTimeStamp)
                    }
                }
                for output in outputs where await output.videoTrackId == inputs.0 {
                    output.mixer(self, didOutput: inputs.1)
                }
            }
        }
        Task {
            for await video in videoIO.output {
                for output in outputs where await output.videoTrackId == UInt8.max {
                    output.mixer(self, didOutput: video)
                }
            }
        }
        Task {
            for await audio in audioIO.output {
                for output in outputs where await output.audioTrackId == UInt8.max {
                    output.mixer(self, didOutput: audio.0, when: audio.1)
                }
            }
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        Task { @MainActor in
            NotificationCenter
                .Publisher(center: .default, name: UIApplication.didEnterBackgroundNotification, object: nil)
                .sink { _ in
                    Task {
                        await self.setInBackground(true)
                    }
                }
                .store(in: &cancellables)
            NotificationCenter
                .Publisher(center: .default, name: UIApplication.willEnterForegroundNotification, object: nil)
                .sink { _ in
                    Task {
                        await self.setInBackground(false)
                    }
                }
                .store(in: &cancellables)
        }
        if #available(tvOS 17.0, *) {
            subscriptions.append(Task {
                for await notification in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification,
                    object: AVAudioSession.sharedInstance()
                ) {
                    didAudioSessionInterruption(notification)
                }
            })
        }
        #endif
    }

    public func stopRunning() async {
        guard isRunning else {
            return
        }
        if #available(tvOS 17.0, *) {
            stopCapturing()
        }
        audioIO.finish()
        videoIO.finish()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        // Wait for the task to finish to prevent memory leaks.
        await Task { @MainActor in
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }.value
        await Task { @ScreenActor in
            displayLink.stopRunning()
            screen.reset()
        }.value
        isRunning = false
    }
}
