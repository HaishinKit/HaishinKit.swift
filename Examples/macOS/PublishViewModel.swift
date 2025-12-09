import AVFoundation
import HaishinKit
import RTCHaishinKit
import SwiftUI

@MainActor
final class PublishViewModel: ObservableObject {
    @Published var currentFPS: FPS = .fps30
    @Published var visualEffectItem: VideoEffectItem = .none
    @Published private(set) var error: Error?
    @Published var isShowError = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var readyState: SessionReadyState = .closed
    private(set) var mixer = MediaMixer(captureSessionMode: .multi)
    private var tasks: [Task<Void, Swift.Error>] = []
    private var session: (any Session)?
    private var currentPosition: AVCaptureDevice.Position = .back
    @ScreenActor private var currentVideoEffect: VideoEffect?

    func startPublishing(_ preference: PreferenceViewModel) {
        Task {
            guard let session else {
                return
            }
            do {
                try await session.connect {
                    Task { @MainActor in
                        self.isShowError = true
                    }
                }
            } catch {
                self.error = error
                self.isShowError = true
                logger.error(error)
            }
        }
    }

    func stopPublishing() {
        Task {
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
            session = try await SessionBuilderFactory.shared.make(preference.makeURL())
                .setMode(.publish)
                .build()
            guard let session else {
                return
            }
            await mixer.addOutput(session.stream)
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
                try await session.stream.setAudioSettings(preference.makeAudioCodecSettings(session.stream.audioSettings))
            }
        } catch {
            self.error = error
            isShowError = true
        }
        do {
            if let session {
                try await session.stream.setVideoSettings(preference.makeVideoCodecSettings(session.stream.videoSettings))
            }
        } catch {
            self.error = error
            isShowError = true
        }
    }

    func startRunning(_ preference: PreferenceViewModel) {
        Task {
            // SetUp a mixer.
            var videoMixerSettings = await mixer.videoMixerSettings
            videoMixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(videoMixerSettings)
            // Attach devices
            let back = AVCaptureDevice.default(for: .video)
            try? await mixer.attachVideo(back, track: 0)
            let audio = AVCaptureDevice.default(for: .audio)
            try? await mixer.attachAudio(audio, track: 0)
            await mixer.startRunning()
            await makeSession(preference)
        }
        Task { @ScreenActor in
            let assetScreenObject = AssetScreenObject()
            assetScreenObject.size = .init(width: 180, height: 180)
            assetScreenObject.layoutMargin = .init(top: 16, left: 16, bottom: 0, right: 0)
            try? assetScreenObject.startReading(AVAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "SampleVideo_360x240_5mb", ofType: "mp4") ?? "")))
            try? await mixer.screen.addChild(assetScreenObject)
            await mixer.screen.size = .init(width: 1280, height: 720)
            await mixer.screen.backgroundColor = NSColor.black.cgColor
        }
    }

    func stopRunning() {
        Task {
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
            try? await mixer.attachVideo(nil)
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
            }
            if let videoEffect = videoEffect.makeVideoEffect() {
                currentVideoEffect = videoEffect
                _ = await mixer.screen.registerVideoEffect(videoEffect)
            }
        }
    }

    func setFrameRate(_ fps: Float64) {
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
