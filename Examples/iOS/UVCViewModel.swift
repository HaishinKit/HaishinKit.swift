import AVFoundation
import HaishinKit
import Photos
import RTCHaishinKit
import SwiftUI

@available(iOS 17.0, *)
@MainActor
final class UVCViewModel: ObservableObject {
    @Published private(set) var error: Error? {
        didSet {
            if error != nil {
                isShowError = true
            }
        }
    }
    @Published var isShowError = false
    @Published private(set) var readyState: SessionReadyState = .closed
    @Published private(set) var isRecording = false
    @Published var isHDREnabled = false {
        didSet {
            Task {
                do {
                    if isHDREnabled {
                        try await mixer.setDynamicRangeMode(.hdr)
                    } else {
                        try await mixer.setDynamicRangeMode(.sdr)
                    }
                } catch {
                    logger.info(error)
                }
            }
        }
    }
    // If you want to use the multi-camera feature, please make create a MediaMixer with a capture mode.
    // let mixer = MediaMixer(captureSesionMode: .multi)
    private(set) var mixer = MediaMixer(captureSessionMode: .single)
    private var tasks: [Task<Void, Swift.Error>] = []
    private var session: (any Session)?
    private var recorder: StreamRecorder?

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { notif in
            guard let device = notif.object as? AVCaptureDevice else { return }
            logger.info(device)
            self.deviceConnected()
        }
    }

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

    func toggleRecording() {
        if isRecording {
            Task {
                do {
                    // To use this in a product, you need to consider recovery procedures in case moving to the Photo Library fails.
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
                recorder = nil
                isRecording = false
            }
        } else {
            Task {
                let recorder = StreamRecorder()
                await mixer.addOutput(recorder)
                do {
                    // When starting a recording while connected to Xcode, it freezes for about 30 seconds. iOS26 + Xcode26.
                    try await recorder.startRecording()
                    isRecording = true
                    self.recorder = recorder
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
                    switch readyState {
                    case .open:
                        UIApplication.shared.isIdleTimerDisabled = false
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
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            logger.error(error)
        }

        Task {
            var videoMixerSettings = await mixer.videoMixerSettings
            videoMixerSettings.mode = .passthrough
            await mixer.setVideoMixerSettings(videoMixerSettings)
            // Attach devices
            do {
                try await mixer.attachVideo(AVCaptureDevice.default(.external, for: .video, position: .unspecified))
            } catch {
                logger.error(error)
            }
            try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            await mixer.startRunning()
            await makeSession(preference)
        }
        Task { @ScreenActor in
            await mixer.screen.size = .init(width: 720, height: 1280)
            await mixer.screen.backgroundColor = UIColor.black.cgColor
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

    private func deviceConnected() {
        Task {
            do {
                try await mixer.attachVideo(AVCaptureDevice.default(.external, for: .video, position: .unspecified))
            } catch {
                logger.error(error)
            }
        }
    }
}

@available(iOS 17.0, *)
extension UVCViewModel: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: MTHKView) {
        Task {
            await mixer.addOutput(view)
        }
    }
}

@available(iOS 17.0, *)
extension UVCViewModel: PiPHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: PiPHKView) {
        Task {
            await mixer.addOutput(view)
        }
    }
}
