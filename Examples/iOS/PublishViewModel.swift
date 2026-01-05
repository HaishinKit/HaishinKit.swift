import AVFoundation
import HaishinKit
import MediaPlayer
import Photos
import RTCHaishinKit
import SwiftUI

@MainActor
final class PublishViewModel: ObservableObject {
    private enum Keys {
        static let currentFPS = "publish_fps"
        static let videoBitRates = "publish_bitrate"
    }

    @Published var currentFPS: FPS = .fps30 {
        didSet {
            UserDefaults.standard.set(currentFPS.rawValue, forKey: Keys.currentFPS)
        }
    }
    @Published var visualEffectItem: VideoEffectItem = .none
    @Published private(set) var error: Error? {
        didSet {
            if error != nil {
                isShowError = true
            }
        }
    }
    @Published var isShowError = false
    @Published var showPreLiveDialog = false
    @Published private(set) var isAudioMuted = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var readyState: SessionReadyState = .closed
    @Published var audioSource: AudioSource = .empty {
        didSet {
            guard audioSource != oldValue else {
                return
            }
            selectAudioSource(audioSource)
        }
    }
    @Published private(set) var audioSources: [AudioSource] = []
    @Published private(set) var isRecording = false
    @Published private(set) var stats: [Stats] = []
    @Published private(set) var currentCamera: String = "Back"
    @Published private(set) var isDualCameraEnabled: Bool = false
    @Published private(set) var isVolumeOn: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var videoDimensions: String = ""
    @Published private(set) var batteryUsed: Float = 0
    @Published private(set) var streamDuration: TimeInterval = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var currentUploadKBps: Int = 0
    private var streamStartBattery: Float = 0
    private var streamStartTime: Date?
    private var batteryTimer: Timer?
    private var durationTimer: Timer?
    @Published var videoBitRates: Double = 2000 {
        didSet {
            UserDefaults.standard.set(videoBitRates, forKey: Keys.videoBitRates)
            Task {
                guard let session else {
                    return
                }
                var videoSettings = await session.stream.videoSettings
                videoSettings.bitRate = Int(videoBitRates * 1000)
                try await session.stream.setVideoSettings(videoSettings)
            }
        }
    }
    private(set) var mixer = MediaMixer()
    private var tasks: [Task<Void, Swift.Error>] = []
    private var session: (any Session)?
    private var recorder: StreamRecorder?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var audioSourceService = AudioSourceService()
    @ScreenActor private var videoScreenObject: VideoTrackScreenObject?
    @ScreenActor private var currentVideoEffect: VideoEffect?
    private var volumeObserver: NSKeyValueObservation?
    private var mtView: MTHKView?
    private var isMixerReady = false

    init() {
        let defaults = UserDefaults.standard

        if let rawValue = defaults.string(forKey: Keys.currentFPS),
           let fps = FPS(rawValue: rawValue) {
            self.currentFPS = fps
        }

        if defaults.object(forKey: Keys.videoBitRates) != nil {
            self.videoBitRates = defaults.double(forKey: Keys.videoBitRates)
        }

        Task { @ScreenActor in
            videoScreenObject = VideoTrackScreenObject()
        }
    }

    func startPublishing(_ preference: PreferenceViewModel, withRecording: Bool = false) {
        Task {
            guard let session else {
                return
            }
            stats.removeAll()

            let recorder = StreamRecorder()
            await mixer.addOutput(recorder)
            self.recorder = recorder

            if withRecording {
                do {
                    try await recorder.startRecording()
                    isRecording = true
                } catch {
                    self.error = error
                    logger.warn(error)
                }
            }

            do {
                try await session.connect {
                    Task { @MainActor in
                        self.isShowError = true
                    }
                }
            } catch {
                self.error = error
                logger.error(error)
            }
        }
    }

    func stopPublishing() {
        Task {
            if isRecording {
                do {
                    if let videoFile = try await recorder?.stopRecording() {
                        Task.detached {
                            try await PHPhotoLibrary.shared().performChanges {
                                let creationRequest = PHAssetCreationRequest.forAsset()
                                creationRequest.addResource(with: .video, fileURL: videoFile, options: nil)
                            }
                        }
                    }
                } catch {
                    logger.warn(error)
                }
                isRecording = false
            }
            if let recorder {
                await mixer.removeOutput(recorder)
                self.recorder = nil
            }
            do {
                try await session?.close()
            } catch {
                logger.error(error)
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            Task {
                do {
                    if let videoFile = try await recorder?.stopRecording() {
                        Task.detached {
                            try await PHPhotoLibrary.shared().performChanges {
                                let creationRequest = PHAssetCreationRequest.forAsset()
                                creationRequest.addResource(with: .video, fileURL: videoFile, options: nil)
                            }
                        }
                    }
                } catch let error as StreamRecorder.Error {
                    switch error {
                    case .failedToFinishWriting(let error):
                        self.error = error
                        if let error {
                            logger.warn(error)
                        }
                    default:
                        self.error = error
                        logger.warn(error)
                    }
                }
                isRecording = false
            }
        } else {
            Task {
                guard let recorder else {
                    logger.warn("Recorder not initialized")
                    return
                }
                do {
                    try await recorder.startRecording()
                    isRecording = true
                } catch {
                    self.error = error
                    logger.warn(error)
                }
                for await error in await recorder.error {
                    switch error {
                    case .failedToAppend(let error):
                        self.error = error
                    default:
                        self.error = error
                    }
                    break
                }
            }
        }
    }

    func toggleAudioMuted() {
        Task {
            if isAudioMuted {
                var settings = await mixer.audioMixerSettings
                var track = settings.tracks[0] ?? .init()
                track.isMuted = false
                settings.tracks[0] = track
                await mixer.setAudioMixerSettings(settings)
                isAudioMuted = false
            } else {
                var settings = await mixer.audioMixerSettings
                var track = settings.tracks[0] ?? .init()
                track.isMuted = true
                settings.tracks[0] = track
                await mixer.setAudioMixerSettings(settings)
                isAudioMuted = true
            }
        }
    }

    func makeSession(_ preference: PreferenceViewModel) async {
        do {
            session = try await SessionBuilderFactory.shared.make(preference.makeURL())
                .setMode(.publish)
                .build()
            guard let session else {
                return
            }
            var videoSettings = await session.stream.videoSettings
            videoSettings.bitRate = Int(videoBitRates * 1000)
            try? await session.stream.setVideoSettings(videoSettings)
            await session.stream.setBitRateStrategy(StatsMonitor({ data in
                Task { @MainActor in
                    self.stats.append(data)
                    if self.stats.count > 60 {
                        self.stats.removeFirst(self.stats.count - 60)
                    }
                    self.currentUploadKBps = data.currentBytesOutPerSecond / 1024
                }
            }))
            await mixer.addOutput(session.stream)
            tasks.append(Task {
                for await readyState in await session.readyState {
                    self.readyState = readyState
                    switch readyState {
                    case .open:
                        UIApplication.shared.isIdleTimerDisabled = false
                        self.startBatteryTracking()
                    case .closed:
                        UIApplication.shared.isIdleTimerDisabled = true
                        self.stopBatteryTracking()
                    default:
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
            })
        } catch {
            self.error = error
        }
        do {
            if let session {
                try await session.stream.setAudioSettings(preference.makeAudioCodecSettings(session.stream.audioSettings))
            }
        } catch {
            self.error = error
        }
        do {
            if let session {
                try await session.stream.setVideoSettings(preference.makeVideoCodecSettings(session.stream.videoSettings))
            }
        } catch {
            self.error = error
        }
    }

    func startRunning(_ preference: PreferenceViewModel) {
        isMixerReady = false
        isDualCameraEnabled = false

        let isGPURendererEnabled = preference.isGPURendererEnabled

        Task {
            tasks.forEach { $0.cancel() }
            tasks.removeAll()

            await audioSourceService.stopRunning()
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
            try? await mixer.attachVideo(nil, track: 0)
            try? await mixer.attachVideo(nil, track: 1)
            if let session {
                await mixer.removeOutput(session.stream)
                try? await session.close()
            }
            session = nil

            mixer = MediaMixer(captureSessionMode: .multi)

            let audioCaptureMode = preference.audioCaptureMode
            await audioSourceService.setUp(preference.audioCaptureMode)
            await mixer.configuration { session in
                switch audioCaptureMode {
                case .audioSource:
                    session.automaticallyConfiguresApplicationAudioSession = true
                case .audioSourceWithStereo:
                    session.automaticallyConfiguresApplicationAudioSession = false
                case .audioEngine:
                    session.automaticallyConfiguresApplicationAudioSession = true
                }
            }
            await mixer.setMonitoringEnabled(DeviceUtil.isHeadphoneConnected())
            var videoMixerSettings = await mixer.videoMixerSettings
            videoMixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(videoMixerSettings)

            await configureScreen(isGPURendererEnabled: isGPURendererEnabled)

            let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            try? await mixer.attachVideo(backCamera, track: 0) { videoUnit in
                videoUnit.isVideoMirrored = false
            }
            try? await mixer.attachVideo(frontCamera, track: 1) { videoUnit in
                videoUnit.isVideoMirrored = true
            }
            var videoMixerSettings2 = await mixer.videoMixerSettings
            videoMixerSettings2.mainTrack = currentPosition == .front ? 1 : 0
            await mixer.setVideoMixerSettings(videoMixerSettings2)
            currentCamera = currentPosition == .front ? "Front" : "Back"
            if audioCaptureMode == .audioSource {
                try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            }
            await audioSourceService.startRunning()
            await mixer.startRunning()

            isMixerReady = true
            if let mtView {
                await mixer.addOutput(mtView)
            }

            do {
                if preference.isHDREnabled {
                    try await mixer.setDynamicRangeMode(.hdr)
                } else {
                    try await mixer.setDynamicRangeMode(.sdr)
                }
            } catch {
                logger.info(error)
            }
            await makeSession(preference)
            let isLandscape = await UIDevice.current.orientation.isLandscape
            await updateVideoEncoderSize(isLandscape: isLandscape)
            let screenSize = await mixer.screen.size
            if let session = self.session {
                let videoSettings = await session.stream.videoSettings
                self.videoDimensions = "Screen: \(Int(screenSize.width))x\(Int(screenSize.height)) | Video: \(videoSettings.videoSize.width)x\(videoSettings.videoSize.height)"
            }
            isLoading = false
        }
        orientationDidChange()
        tasks.append(Task {
            for await buffer in await audioSourceService.buffer {
                await mixer.append(buffer.0, when: buffer.1)
            }
        })
        tasks.append(Task {
            for await sources in await audioSourceService.sourcesUpdates() {
                audioSources = sources
                if let first = sources.first, audioSource == .empty {
                    audioSource = first
                }
            }
        })
        startVolumeMonitoring()
    }

    @ScreenActor
    private func configureScreen(isGPURendererEnabled: Bool) async {
        await mixer.screen.isGPURendererEnabled = isGPURendererEnabled
        await mixer.screen.size = .init(width: 720, height: 1280)
        await mixer.screen.backgroundColor = UIColor.black.cgColor
    }

    private func startVolumeMonitoring() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(true)
        isVolumeOn = audioSession.outputVolume > 0
        volumeObserver = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                if let volume = change.newValue {
                    self?.isVolumeOn = volume > 0
                }
            }
        }
    }

    private func stopVolumeMonitoring() {
        volumeObserver?.invalidate()
        volumeObserver = nil
    }

    func stopRunning() {
        isMixerReady = false
        stopVolumeMonitoring()
        Task {
            await audioSourceService.stopRunning()
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
            try? await mixer.attachVideo(nil, track: 0)
            try? await mixer.attachVideo(nil, track: 1)
            if let session {
                await mixer.removeOutput(session.stream)
            }
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
        }
    }

    func flipCamera() {
        Task {
            var videoMixerSettings = await mixer.videoMixerSettings
            if videoMixerSettings.mainTrack == 0 {
                videoMixerSettings.mainTrack = 1
                await mixer.setVideoMixerSettings(videoMixerSettings)
                currentPosition = .front
                currentCamera = "Front"
                if isTorchEnabled {
                    await mixer.setTorchEnabled(false)
                    isTorchEnabled = false
                }
                Task { @ScreenActor in
                    videoScreenObject?.track = 0
                }
            } else {
                videoMixerSettings.mainTrack = 0
                await mixer.setVideoMixerSettings(videoMixerSettings)
                currentPosition = .back
                currentCamera = "Back"
                Task { @ScreenActor in
                    videoScreenObject?.track = 1
                }
            }
        }
    }

    func setVisualEffet(_ videoEffect: VideoEffectItem) {
        Task { @ScreenActor in
            if let currentVideoEffect {
                _ = await mixer.screen.unregisterVideoEffect(currentVideoEffect)
            }
            if let videoEffect = videoEffect.makeVideoEffect() {
                currentVideoEffect = videoEffect
                _ = await mixer.screen.registerVideoEffect(videoEffect)
            }
        }
    }

    func toggleTorch() {
        Task {
            await mixer.setTorchEnabled(!isTorchEnabled)
            isTorchEnabled.toggle()
        }
    }

    func toggleDualCamera() {
        let isEnabled = isDualCameraEnabled
        let position = currentPosition
        Task { @ScreenActor in
            if isEnabled {
                if let videoScreenObject {
                    try? await mixer.screen.removeChild(videoScreenObject)
                }
                await MainActor.run { isDualCameraEnabled = false }
            } else {
                if let videoScreenObject {
                    videoScreenObject.size = .init(width: 400, height: 224)
                    videoScreenObject.cornerRadius = 8.0
                    videoScreenObject.track = position == .front ? 0 : 1
                    videoScreenObject.verticalAlignment = .top
                    videoScreenObject.horizontalAlignment = .right
                    videoScreenObject.layoutMargin = .init(top: 32, left: 0, bottom: 0, right: 32)
                    videoScreenObject.invalidateLayout()
                    try? await mixer.screen.addChild(videoScreenObject)
                }
                await MainActor.run { isDualCameraEnabled = true }
            }
        }
    }

    func setFrameRate(_ fps: Float64) {
        Task {
            do {
                try? await mixer.configuration(video: 0) { video in
                    do {
                        try video.setFrameRate(fps)
                    } catch {
                        logger.error(error)
                    }
                }
                try? await mixer.configuration(video: 1) { video in
                    do {
                        try video.setFrameRate(fps)
                    } catch {
                        logger.error(error)
                    }
                }
                try await mixer.setFrameRate(fps)
                if var videoSettings = await session?.stream.videoSettings {
                    videoSettings.expectedFrameRate = fps
                    try? await session?.stream.setVideoSettings(videoSettings)
                }
            } catch {
                logger.error(error)
            }
        }
    }

    func orientationDidChange() {
        Task { @ScreenActor in
            await mixer.setVideoOrientation(.portrait)
            await mixer.screen.size = .init(width: 720, height: 1280)
            let screenSize = await mixer.screen.size
            Task { @MainActor in
                await self.updateVideoEncoderSize(isLandscape: false)
                if let session = self.session {
                    let videoSettings = await session.stream.videoSettings
                    self.videoDimensions = "Screen: \(Int(screenSize.width))x\(Int(screenSize.height)) | Video: \(videoSettings.videoSize.width)x\(videoSettings.videoSize.height)"
                } else {
                    self.videoDimensions = "Screen: \(Int(screenSize.width))x\(Int(screenSize.height))"
                }
            }
        }
    }

    private func updateVideoEncoderSize(isLandscape: Bool) async {
        guard let session else { return }
        var videoSettings = await session.stream.videoSettings
        let targetSize: CGSize = isLandscape
            ? CGSize(width: 1280, height: 720)
            : CGSize(width: 720, height: 1280)
        if videoSettings.videoSize != targetSize {
            videoSettings.videoSize = targetSize
            try? await session.stream.setVideoSettings(videoSettings)
        }
    }

    private func startBatteryTracking() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        streamStartBattery = UIDevice.current.batteryLevel
        streamStartTime = Date()
        batteryUsed = 0
        streamDuration = 0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryStats()
            }
        }
    }

    private func stopBatteryTracking() {
        durationTimer?.invalidate()
        durationTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        updateBatteryStats()
    }

    private func updateDuration() {
        guard let startTime = streamStartTime else { return }
        streamDuration = Date().timeIntervalSince(startTime)
    }

    private func updateBatteryStats() {
        let currentBattery = UIDevice.current.batteryLevel
        if currentBattery >= 0 && streamStartBattery >= 0 {
            batteryUsed = (streamStartBattery - currentBattery) * 100
        }
        thermalState = ProcessInfo.processInfo.thermalState
    }

    private func selectAudioSource(_ audioSource: AudioSource) {
        Task {
            try await audioSourceService.selectAudioSource(audioSource)
            await mixer.stopCapturing()
            try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            await mixer.startCapturing()
        }
    }
}

extension PublishViewModel: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
            self.mtView = view
            if isMixerReady {
                await mixer.addOutput(view)
            }
        }
    }
}
