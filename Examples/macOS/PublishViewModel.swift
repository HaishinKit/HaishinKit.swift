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
    @Published private(set) var networkReport: NetworkMonitorReport?
    @Published private(set) var measuredFPS: UInt16?
    @Published private(set) var activeEncodingDescription: String?
    @Published private(set) var captureIsStarting = true
    @Published private(set) var captureIssue: String?
    @Published var currentFPS: FPS = .fps30
    @Published var visualEffectItem: VideoEffectItem = .none
    @Published private(set) var error: Error?
    @Published var isShowError = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    private(set) var mixer = MediaMixer(captureSessionMode: .multi)
    lazy var screenCapture = ScreenCaptureSource(mixer: mixer)
    private var tasks: [Task<Void, Swift.Error>] = []
    private var telemetryTask: Task<Void, Never>?
    private var telemetry: PublishTelemetry?
    private var startupTask: Task<Void, Never>?
    private var publishingTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var session: (any StreamSession)?
    private var currentPosition: AVCaptureDevice.Position = .back
    @ScreenActor private var currentVideoEffect: VideoEffect?
    @ScreenActor private var didAddSampleOverlays = false

    func startPublishing(_ preference: PreferenceViewModel) {
        guard !isBusy, readyState == .closed else { return }
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
            await makeSession(preference)
            guard let session, !Task.isCancelled else { return }
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

    func makeSession(_ preference: PreferenceViewModel) async {
        // Make session.
        do {
            session = try await StreamSessionBuilderFactory.shared.make(preference.makeURL())
                .setMode(.publish)
                .build()
            guard let session else {
                return
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
        }
        do {
            if let session {
                var video = await preference.makeVideoCodecSettings(session.stream.videoSettings)
                video.bitRate = videoBitRate
                video.videoSize = outputResolution.size
                video.profileLevel = outputCodec.profileLevel
                video.expectedFrameRate = currentFPS.frameRate
                video.isHardwareAcceleratedEnabled = useHardwareEncoder
                try await session.stream.setVideoSettings(video)
                let audio = await session.stream.audioSettings
                activeEncodingDescription = "\(outputResolution.rawValue) · \(outputCodec.rawValue) · \(String(describing: audio.format).uppercased()) \(audio.bitRate / 1000) kbps"
            }
        } catch {
            self.error = error
            isShowError = true
        }
    }

    func startRunning(_ preference: PreferenceViewModel) {
        let previousShutdown = shutdownTask
        startupTask = Task {
            await previousShutdown?.value
            guard !Task.isCancelled else { return }
            captureIsStarting = true
            defer { captureIsStarting = false }
            captureIssue = await MacCaptureCoordinator.shared.activate(mixer, frameRate: currentFPS.frameRate, useAudioEngine: preference.audioCaptureMode == .audioEngine, microphoneEnabled: UserDefaults.standard.bool(forKey: "macos.capture.microphoneEnabled"))
        }
        Task { @ScreenActor in
            await mixer.screen.size = .init(width: 1280, height: 720)
            await mixer.screen.backgroundColor = NSColor.black.cgColor
            guard !didAddSampleOverlays else { return }
            didAddSampleOverlays = true

            let assetScreenObject = AssetScreenObject(id: "example-overlay-video")
            assetScreenObject.isLooping = true
            assetScreenObject.size = .init(width: 180, height: 180)
            assetScreenObject.layoutMargin = .init(top: 16, left: 16, bottom: 0, right: 0)
            try? assetScreenObject.startReading(AVURLAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "SampleVideo_360x240_5mb", ofType: "mp4") ?? "")))
            try? await mixer.screen.addChild(assetScreenObject)

            let image = ImageScreenObject(id: "example-overlay-image")
            image.size = .init(width: 120, height: 120)
            image.horizontalAlignment = .right
            image.verticalAlignment = .bottom
            image.layoutMargin = .init(top: 0, left: 0, bottom: 16, right: 16)
            let appIconFile = URL(fileURLWithPath: Bundle.main.path(forResource: "AppIcon", ofType: "png") ?? "")
            if let nsImage = NSImage(contentsOf: appIconFile), let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ciImage = CIImage(cgImage: cgImage)
                image.ciImage = ciImage
            }
            try? await mixer.screen.addChild(image)
        }
    }

    func requestCameraAccess(_ preference: PreferenceViewModel) {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            stopRunning()
            startRunning(preference)
        }
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
        Task { @ScreenActor in
            if let currentVideoEffect {
                _ = await mixer.screen.unregisterVideoEffect(currentVideoEffect)
                self.currentVideoEffect = nil
            }
            if let videoEffect = videoEffect.makeVideoEffect() {
                currentVideoEffect = videoEffect
                _ = await mixer.screen.registerVideoEffect(videoEffect)
            }
        }
    }

    func setFrameRate(_ fps: Float64) {
        screenCapture.setFrameRate(Int(fps))
        Task {
            do {
                // Sets to input frameRate.
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
                // Sets to output frameRate.
                try await mixer.setFrameRate(fps)
            } catch {
                logger.error(error)
            }
        }
    }
}

extension PublishViewModel: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: HaishinKit.MTHKView) {
        Task {
            await mixer.addOutput(view)
        }
    }
}
