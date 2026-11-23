import AVFoundation
import HaishinKit
import RTCHaishinKit
import RTMPHaishinKit
import SwiftUI

@MainActor
final class PublishViewModel: ObservableObject {
    @Published private(set) var isBusy = false
    @Published var videoBitRate = 2_500_000
    @Published var audioBitRate = 64_000
    @Published var outputResolution: OutputResolution = .hd720
    @Published var outputCodec: OutputVideoCodec = .h264
    @Published var useHardwareEncoder = true
    @Published private(set) var mixerDynamicRangeMode: DynamicRangeMode = .sdr
    @Published private(set) var isChangingDynamicRange = false
    @Published private(set) var dynamicRangeIssue: String?
    @Published private(set) var networkReport: NetworkMonitorReport?
    @Published private(set) var measuredFPS: UInt16?
    @Published private(set) var activeEncodingDescription: String?
    @Published private(set) var captureIsStarting = true
    @Published private(set) var captureIssue: String?
    @Published var mixerFPS: FPS = .fps30
    @Published var currentFPS: FPS = .fps30
    @Published var visualEffectItem: VideoEffectItem = .none
    @Published private(set) var error: Error?
    @Published var isShowError = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    private(set) var mixer = MediaMixer(captureSessionMode: .multi)
    lazy var screenCapture = ScreenCaptureSource(mixer: mixer)
    lazy var sceneEditor = SceneEditorModel(mixer: mixer)
    private var tasks: [Task<Void, Swift.Error>] = []
    private var telemetryTask: Task<Void, Never>?
    private var telemetry: PublishTelemetry?
    private var startupTask: Task<Void, Never>?
    private var publishingTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var session: (any StreamSession)?
    private var currentPosition: AVCaptureDevice.Position = .back
    private weak var previewView: MTHKView?

    var encodingConfigurationIssue: String? {
        guard mixerDynamicRangeMode != outputCodec.dynamicRangeMode else { return nil }
        return mixerDynamicRangeMode == .hdr
            ? String(localized: "Select HEVC Main10 (HDR), or turn off Mixer HDR before publishing.")
            : String(localized: "Turn on Mixer HDR to publish with HEVC Main10 (HDR).")
    }

    func setMixerDynamicRangeMode(_ mode: DynamicRangeMode) {
        guard !isBusy, readyState == .closed, !captureIsStarting, !isChangingDynamicRange else { return }
        isChangingDynamicRange = true
        dynamicRangeIssue = nil
        Task {
            defer { isChangingDynamicRange = false }
            do {
                try await mixer.setDynamicRangeMode(mode)
                mixerDynamicRangeMode = await mixer.dynamicRangeMode
                previewView?.setDynamicRangeMode(mixerDynamicRangeMode)
            } catch {
                dynamicRangeIssue = String(localized: "Couldn't change Mixer HDR: \(error.localizedDescription)")
            }
        }
    }

    func startPublishing(_ preference: PreferenceViewModel) {
        guard !isBusy, !isChangingDynamicRange, readyState == .closed, encodingConfigurationIssue == nil else { return }
        isBusy = true
        publishingTask = Task {
            defer { isBusy = false }
            if let session { await mixer.removeOutput(session.stream) }
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
            telemetryTask?.cancel()
            networkReport = nil
            measuredFPS = nil
            activeEncodingDescription = nil
            session = nil
            guard await makeSession(preference), let session, !Task.isCancelled else { return }
            do {
                try await session.connect {
                    Task { @MainActor in
                        self.isShowError = true
                    }
                }
                if Task.isCancelled { try? await session.close() }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                self.isShowError = true
                logger.error(error)
            }
        }
    }

    func stopPublishing() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await session?.close()
            } catch {
                logger.error(error)
            }
        }
    }

    func makeSession(_ preference: PreferenceViewModel) async -> Bool {
        // Make session.
        do {
            session = try await StreamSessionBuilderFactory.shared.make(preference.makeURL())
                .setMode(.publish)
                .build()
            guard let session else {
                return false
            }
            await mixer.addOutput(session.stream)
            let telemetry = PublishTelemetry()
            self.telemetry = telemetry
            await session.stream.setBitRateStrategy(telemetry)
            telemetryTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.networkReport = self.readyState == .open ? await telemetry.report : nil
                    if self.readyState == .open, let stream = await session.stream as? RTMPStream {
                        self.measuredFPS = await stream.currentFPS
                    } else { self.measuredFPS = nil }
                    try? await Task.sleep(for: .seconds(1))
                }
            }

            tasks.append(Task {
                for await readyState in await session.readyState {
                    self.readyState = readyState
                }
            })
        } catch {
            self.error = error
            isShowError = true
            return false
        }
        do {
            if let session {
                var audio = await preference.makeAudioCodecSettings(session.stream.audioSettings)
                audio.bitRate = audioBitRate
                try await session.stream.setAudioSettings(audio)
            }
        } catch {
            self.error = error
            isShowError = true
            return false
        }
        do {
            if let session {
                var video = await preference.makeVideoCodecSettings(session.stream.videoSettings)
                video.bitRate = videoBitRate
                video.videoSize = outputResolution.size
                video.profileLevel = outputCodec.profileLevel
                video.expectedFrameRate = mixerFPS.frameRate
                video.isHardwareAcceleratedEnabled = useHardwareEncoder
                try await session.stream.setVideoSettings(video)
                let audio = await session.stream.audioSettings
                activeEncodingDescription = "\(outputResolution.rawValue) · \(outputCodec.rawValue) · \(String(describing: audio.format).uppercased()) \(audio.bitRate / 1000) kbps"
            }
        } catch {
            self.error = error
            isShowError = true
            return false
        }
        return true
    }

    func startRunning(_ preference: PreferenceViewModel) {
        let previousShutdown = shutdownTask
        startupTask = Task {
            await previousShutdown?.value
            guard !Task.isCancelled else { return }
            captureIsStarting = true
            defer { captureIsStarting = false }
            captureIssue = await MacCaptureCoordinator.shared.activate(mixer, frameRate: currentFPS.frameRate, useAudioEngine: preference.audioCaptureMode == .audioEngine, microphoneEnabled: UserDefaults.standard.bool(forKey: "macos.capture.microphoneEnabled"))
            guard !Task.isCancelled else { return }
            await configureCaptureFrameRate(currentFPS.frameRate)
            try? await mixer.setFrameRate(mixerFPS.frameRate)
            await sceneEditor.start()
        }
    }

    func requestCameraAccess(_ preference: PreferenceViewModel) {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            stopRunning()
            startRunning(preference)
        }
    }

    func openSceneFileWhenReady(_ url: URL) async {
        await startupTask?.value
        while (captureIsStarting || sceneEditor.busy) && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
        guard !Task.isCancelled else { return }
        sceneEditor.openSceneFile(url)
    }

    func stopRunning() {

        startupTask?.cancel()
        publishingTask?.cancel()
        let startup = startupTask
        let publishing = publishingTask
        shutdownTask = Task {
            await startup?.value
            await publishing?.value
            telemetryTask?.cancel()
            telemetryTask = nil
            networkReport = nil
            measuredFPS = nil
            await sceneEditor.stop()
            await screenCapture.stop(restoreCamera: false)
            try? await session?.close()
            await MacCaptureCoordinator.shared.deactivate(mixer)
            if let session {
                await mixer.removeOutput(session.stream)
            }
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
        }
    }

    func setVisualEffet(_ videoEffect: VideoEffectItem) {
        sceneEditor.setEffect(videoEffect)
    }

    func setMixerFrameRate(_ fps: Float64) {
        Task {
            do {
                try await mixer.setFrameRate(fps)
                if let session {
                    var video = await session.stream.videoSettings
                    video.expectedFrameRate = fps
                    try await session.stream.setVideoSettings(video)
                }
            } catch {
                self.error = error
                isShowError = true
            }
        }
    }

    func setFrameRate(_ fps: Float64) {
        Task { await configureCaptureFrameRate(fps) }
    }

    private func configureCaptureFrameRate(_ fps: Float64) async {
        screenCapture.setFrameRate(Int(fps))
        for track: UInt8 in [0, 1] {
            try? await mixer.configuration(video: track) { video in
                do { try video.setFrameRate(fps) }
                catch { logger.error(error) }
            }
        }
    }
}

extension PublishViewModel: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: HaishinKit.MTHKView) {
        Task { @MainActor in
            previewView = view
            view.setDynamicRangeMode(mixerDynamicRangeMode)
            await mixer.addOutput(view)
        }
    }
}
