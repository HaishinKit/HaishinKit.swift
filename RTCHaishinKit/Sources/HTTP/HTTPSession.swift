import Foundation
import HaishinKit

actor HTTPSession: StreamSession {
    var connected: Bool {
        get async {
            peerConnection?.connectionState == .connected
        }
    }

    @AsyncStreamed(.closed)
    private(set) var readyState: AsyncStream<StreamSessionReadyState>

    var stream: any StreamConvertible {
        _stream
    }

    private let uri: URL
    private var location: URL?
    private var maxRetryCount: Int = 0
    private var _stream = RTCStream()
    private var mode: StreamSessionMode
    private var configuration: HTTPSessionConfiguration?
    private var peerConnection: RTCPeerConnection?
    private var receivingTracks: [RTCTrack] = []

    init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        logger.level = .debug
        self.uri = uri
        self.mode = mode
        if let configuration = configuration as? HTTPSessionConfiguration {
            self.configuration = configuration
        }
    }

    func setMaxRetryCount(_ maxRetryCount: Int) {
        self.maxRetryCount = maxRetryCount
    }

    func connect(_ disconnected: @Sendable @escaping () -> Void) async throws {
        guard _readyState.value == .closed else {
            return
        }
        guard let scheme = uri.scheme, ["http", "https"].contains(scheme), let host = uri.host, !host.isEmpty else {
            throw URLError(.badURL)
        }
        _readyState.value = .connecting
        do {
            let offer = try await makeOffer()
            guard let peerConnection else { throw URLError(.cancelled) }
            let answer = try await requestOffer(uri, offer: offer)
            try peerConnection.setRemoteDesciption(answer, type: .answer)
            _readyState.value = .open
        } catch {
            logger.warn(error)
            await _stream.close()
            peerConnection?.close()
            receivingTracks.removeAll()
            _readyState.value = .closed
            throw error
        }
    }

    func close() async throws {
        // Preserve the existing contract: callers cancel/await negotiation before closing.
        guard _readyState.value == .open else { return }
        _readyState.value = .closing
        let location = location
        self.location = nil
        await _stream.close()
        peerConnection?.close()
        peerConnection = nil
        receivingTracks.removeAll()
        _readyState.value = .closed
        if let location {
            var request = URLRequest(url: location)
            request.httpMethod = "DELETE"
            _ = try await URLSession.shared.data(for: request)
        }
    }

    private func requestOffer(_ url: URL, offer: String) async throws -> String {
        logger.debug(offer)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let location = response.value(forHTTPHeaderField: "Location") {
            self.location = URL(string: location, relativeTo: url)?.absoluteURL
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func makeOffer() async throws -> String {
        let peer = try await makePeerConnection()
        peerConnection = peer
        try peer.setLocalDesciption(.offer)
        // Native SDP generation is asynchronous. Never POST an empty or incomplete offer.
        for _ in 0..<250 {
            try Task.checkCancellation()
            let offer = try peer.createOffer()
            if offer.contains("a=ice-ufrag:"), offer.contains("a=candidate:") { return offer }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw URLError(.timedOut)
    }

    private func makePeerConnection()
 async throws -> RTCPeerConnection {
        let peerConnection = try RTCPeerConnection(configuration)
        peerConnection.delegate = self
        switch mode {
        case .publish:
            let audioSettings = await _stream.audioSettings
            try peerConnection.addTrack(AudioStreamTrack(audioSettings), stream: _stream)
            let videoSettings = await _stream.videoSettings
            try peerConnection.addTrack(VideoStreamTrack(videoSettings), stream: _stream)
        case .playback:
            await _stream.setDirection(.recvonly)
            receivingTracks.append(try peerConnection.addTrack(.audio, stream: _stream))
            receivingTracks.append(try peerConnection.addTrack(.video, stream: _stream))
        }
        return peerConnection
    }
}

extension HTTPSession: RTCPeerConnectionDelegate {
    // MARK: RTCPeerConnectionDelegate
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged state: RTCPeerConnection.ConnectionState) {
        Task {
            if state == .connected {
                if await mode == .publish {
                    await _stream.setDirection(.sendonly)
                }
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState) {
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState) {
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged gatheringState: RTCPeerConnection.IceGatheringState) {
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate) {
    }

    nonisolated func peerConnection(_ peerConneciton: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }
}
