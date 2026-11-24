import AVFoundation
import Combine
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit

/// A window owns its connection; editing the endpoint never changes a running session.
@MainActor
final class VisionStudioModel: ObservableObject {
    @Published var server = Preference.default.uri
    @Published var publishing = UserDefaults.standard.bool(forKey: "visionos.studio.publishing") {
        didSet { UserDefaults.standard.set(publishing, forKey: "visionos.studio.publishing") }
    }
    @Published var streamName = Preference.default.streamName
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var busy = false
    @Published private(set) var active = false
    @Published private(set) var errorMessage: String?

    private let mixer = MediaMixer()
    private let signal = ExampleTestSignal()
    @Published private(set) var signalRunning = false

    private var session: (any StreamSession)?
    private var stateTask: Task<Void, Never>?
    private var generation = UUID()
    private var view: PiPHKView?
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())

    var usesRTMP: Bool { ["rtmp", "rtmps"].contains(URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased() ?? "") }

    var sourceLabel: String {
        guard let url = endpoint else { return visionText("No valid source") }
        return "\(url.scheme?.uppercased() ?? "") · \(url.host ?? "")"
    }

    var status: String {
        if busy { return visionText(active ? "Connecting…" : "Stopping…") }
        if errorMessage != nil { return visionText("Connection failed") }
        switch readyState {
        case .open: return visionText(publishing ? "Live" : "Playing")
        case .connecting: return visionText("Connecting…")
        case .closing: return visionText("Stopping…")
        case .closed: return visionText("Standby")
        }
    }

    var validationMessage: String? {
        endpoint == nil ? visionText("Enter a valid RTMP/RTMPS URL and stream name, or an SRT caller URL with a port.") : nil
    }

    private var endpoint: URL? {
        VisionStudioEndpoint.make(server: server, streamName: streamName)
    }


    func clearError() {
        guard !active, !busy else { return }
        errorMessage = nil
    }

    func play() async {
        guard !busy, !active else { return }
        guard let url = endpoint else { errorMessage = validationMessage; return }
        busy = true
        active = true
        errorMessage = nil
        let id = UUID()
        generation = id
        // Choose the known factory directly, without racing app-start registration.
        let next = url.scheme?.lowercased() == "srt"
            ? SRTSessionFactory().make(url, mode: publishing ? .publish : .playback, configuration: nil)
            : RTMPSessionFactory().make(url, mode: publishing ? .publish : .playback, configuration: nil)
        session = next
        do {
            await next.setMaxRetryCount(0)
            if publishing {
                let media = await next.stream
                var video = await media.videoSettings
                video.videoSize = CGSize(width: 1280, height: 720)
                video.bitRate = 2_500_000
                video.expectedFrameRate = 30
                #if targetEnvironment(simulator)
                video.isHardwareAcceleratedEnabled = false
                #endif
                try await media.setVideoSettings(video)
                try await media.setAudioSettings(.init(bitRate: 128_000, sampleRate: 48_000))
                if let srt = media as? SRTStream {
                    await srt.setExpectedMedias([.audio, .video])
                }
                guard generation == id else { return }
                await mixer.setVideoMixerSettings(.init(mode: .passthrough))
                await mixer.setAudioMixerSettings(.init(sampleRate: 48_000, channels: 2))
                try await mixer.setFrameRate(30)
                await mixer.addOutput(media)
                if let view { await mixer.addOutput(view) }
                await mixer.startRunning()
                guard generation == id else { await mixer.stopRunning(); return }
                try signal.start(mixer: mixer)
                signalRunning = true
            } else {
                if let view { await next.stream.addOutput(view) }
                await next.stream.attachAudioPlayer(audioPlayer)
            }
            guard generation == id else { return }
            stateTask = Task { [weak self] in
                for await state in await next.readyState {
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    self.readyState = state
                }
            }
            try await next.connect { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    await self.stop()
                    self.errorMessage = visionText("The stream disconnected. Check the server and try again.")
                }
            }
            guard generation == id else {
                try? await next.close()
                return
            }
        } catch {
            guard generation == id else {
                try? await next.close()
                return
            }
            await stop()
            // Avoid leaking URL credentials/stream keys from raw transport errors.
            errorMessage = visionText("Check your server address, stream name and network, then try again.")
        }
        if generation == id { busy = false }
    }

    func stop() async {
        guard let previous = session else { return }
        generation = UUID()
        stateTask?.cancel()
        stateTask = nil
        session = nil
        active = false
        busy = true
        readyState = .closing
        signal.stop()
        signalRunning = false
        let media = await previous.stream
        await media.attachAudioPlayer(nil)
        if let view { await media.removeOutput(view) }
        await mixer.removeOutput(media)
        if let view { await mixer.removeOutput(view) }
        await mixer.stopRunning()
        try? await previous.close()
        view?.layer.flushAndRemoveImage()
        readyState = .closed
        busy = false
    }
}

extension VisionStudioModel: PiPHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: PiPHKView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.view = view
            if self.publishing && self.signalRunning {
                await self.mixer.addOutput(view)
            } else if !self.publishing, let session = self.session {
                await session.stream.addOutput(view)
            }
        }
    }
}
