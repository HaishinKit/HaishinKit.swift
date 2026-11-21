import AVFoundation
import HaishinKit

/// Serializes device ownership across windows and the publisher lifecycle-test sheet.
actor MacCaptureCoordinator {
    static let shared = MacCaptureCoordinator()
    private var microphoneCapture: MacMicrophoneCapture?
    private var activeMixer: MediaMixer?
    private var tail: Task<Void, Never>?

    func activate(_ mixer: MediaMixer, frameRate: Double, useAudioEngine: Bool, microphoneEnabled: Bool) async -> String? {
        let previous = tail
        let operation = Task { () -> String? in
            await previous?.value
            if let activeMixer, activeMixer !== mixer {
                await release(activeMixer)
            }
            activeMixer = mixer
            var settings = await mixer.videoMixerSettings
            settings.mode = .offscreen
            await mixer.setVideoMixerSettings(settings)
            var issues: [String] = []
            let cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            let camera = cameraAllowed ? AVCaptureDevice.default(for: .video) : nil
            if camera == nil { issues.append("Camera unavailable or access not granted. You can share a screen or window instead.") }
            do { try await mixer.attachVideo(camera, track: 0) }
            catch { issues.append("Camera: \(error.localizedDescription)") }
            let microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let microphone = microphoneEnabled && microphoneAllowed ? AVCaptureDevice.default(for: .audio) : nil
            if microphone == nil { issues.append(microphoneEnabled ? "Microphone unavailable or access not granted." : "Microphone is off. Enable it in Settings → Capture.") }
            do { try await mixer.attachAudio(useAudioEngine || !microphoneEnabled ? nil : microphone, track: 0) }
            catch { issues.append("Microphone: \(error.localizedDescription)") }
            try? await mixer.setFrameRate(frameRate)
            await mixer.startRunning()
            if useAudioEngine, microphone != nil {
                let capture = MacMicrophoneCapture(mixer: mixer)
                do { try capture.start(); microphoneCapture = capture }
                catch { issues.append("Microphone: \(error.localizedDescription)") }
            }
            return issues.isEmpty ? nil : issues.joined(separator: "\n")
        }
        tail = Task { _ = await operation.value }
        return await operation.value
    }

    func deactivate(_ mixer: MediaMixer) async {
        let previous = tail
        let operation = Task {
            await previous?.value
            guard activeMixer === mixer else { return }
            await release(mixer)
            activeMixer = nil
        }
        tail = operation
        await operation.value
    }

    private func release(_ mixer: MediaMixer) async {
        microphoneCapture?.stop()
        microphoneCapture = nil
        await mixer.stopRunning()
        try? await mixer.attachAudio(nil)
        try? await mixer.attachVideo(nil)
    }
}
