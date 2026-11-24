import AVFoundation
import Combine
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit

/// A window owns its connection; editing the endpoint never changes a running session.
@MainActor
final class VisionPlaybackModel: ObservableObject {
    @Published var server = Preference.default.uri
    @Published var streamName = Preference.default.streamName
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var busy = false
    @Published private(set) var active = false
    @Published private(set) var errorMessage: String?

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
        case .open: return visionText("Playing")
        case .connecting: return visionText("Connecting…")
        case .closing: return visionText("Stopping…")
        case .closed: return visionText("Standby")
        }
    }

    var validationMessage: String? {
        endpoint == nil ? visionText("Enter a valid RTMP/RTMPS URL and stream name, or an SRT URL with a port.") : nil
    }

    private var endpoint: URL? {
        Self.endpoint(server: server, streamName: streamName)
    }

    static func endpoint(server: String, streamName: String) -> URL? {
        let input = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: input), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty, let url = parts.url else { return nil }
        switch scheme {
        case "rtmp", "rtmps":
            let name = streamName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return url.appendingPathComponent(name)
        case "srt":
            guard let port = parts.port, (1...65535).contains(port) else { return nil }
            return url
        default: return nil
        }
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
            ? SRTSessionFactory().make(url, mode: .playback, configuration: nil)
            : RTMPSessionFactory().make(url, mode: .playback, configuration: nil)
        session = next
        await next.setMaxRetryCount(0)
        if let view { await next.stream.addOutput(view) }
        await next.stream.attachAudioPlayer(audioPlayer)
        guard generation == id else { return }
        stateTask = Task { [weak self] in
            for await state in await next.readyState {
                guard !Task.isCancelled, let self, self.generation == id else { return }
                self.readyState = state
            }
        }
        do {
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
        try? await previous.close()
        readyState = .closed
        busy = false
    }
}

extension VisionPlaybackModel: PiPHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: PiPHKView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.view = view
            if let session = self.session { await session.stream.addOutput(view) }
        }
    }
}
