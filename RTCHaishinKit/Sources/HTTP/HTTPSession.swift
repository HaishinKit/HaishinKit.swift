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
    // Playback tracks MUST be retained: RTCTrack.deinit calls rtcDeleteTrack, so
    // discarding the addTrack(...) return value deletes the native track before
    // negotiation → "No DataChannel or Track to negotiate" → connect always fails.
    private var tracks: [RTCTrack] = []

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
        _readyState.value = .connecting
        do {
            do {
                try await attemptConnect(videoOnly: false)
            } catch let error as URLError where mode == .playback && error.localizedDescription.contains("codecs not supported") {
                // MediaMTX hard-rejects ("codecs not supported by client", HTTP 400)
                // any offer whose audio m-line it cannot satisfy — i.e. whenever the
                // published stream has no WebRTC-compatible (Opus) audio track, which
                // is every AAC/no-audio stream. Browsers slip through; this client's
                // single-opus audio section does not. Retry once with a video-only
                // offer: video plays for AAC/no-audio streams, and Opus streams keep
                // full audio+video via the first attempt.
                logger.warn("WHEP offer rejected for audio codec; retrying video-only")
                teardownAttempt()
                try await attemptConnect(videoOnly: true)
            }
            _readyState.value = .open
        } catch {
            logger.warn(error)
            await _stream.close()
            teardownAttempt()
            _readyState.value = .closed
            throw error
        }
    }

    private func teardownAttempt() {
        tracks.removeAll()
        peerConnection?.close()
        peerConnection = nil
    }

    private func attemptConnect(videoOnly: Bool) async throws {
        let peerConnection = try makePeerConnection()
        switch mode {
        case .publish:
            let audioSettings = await _stream.audioSettings
            try peerConnection.addTrack(AudioStreamTrack(audioSettings), stream: _stream)
            let videoSettings = await _stream.videoSettings
            try peerConnection.addTrack(VideoStreamTrack(videoSettings), stream: _stream)
        case .playback:
            await _stream.setDirection(.recvonly)
            // Retain the returned tracks: RTCTrack.deinit calls rtcDeleteTrack, so
            // discarding them deletes the native tracks before negotiation
            // ("No DataChannel or Track to negotiate").
            if !videoOnly {
                tracks.append(try peerConnection.addTrack(.audio, stream: _stream))
            }
            tracks.append(try peerConnection.addTrack(.video, stream: _stream))
        }
        self.peerConnection = peerConnection
        try peerConnection.setLocalDesciption(.offer)
        // Canonical libdatachannel (vanilla-ICE) WHIP/WHEP flow: createOffer()
        // requires disableAutoNegotiation and returns RTC_ERR_FAILURE under the
        // default auto-negotiation config. Instead, wait for ICE gathering to
        // complete, then read the local description back — it now contains the
        // gathered candidates, which this non-trickle client (no PATCH) needs
        // in the offer for the server to reach it.
        for _ in 0..<60 where peerConnection.iceGatheringState != .complete {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let offer = try peerConnection.currentLocalDescription()
        let answer = try await requestOffer(uri, offer: offer)
        try peerConnection.setRemoteDesciption(answer, type: .answer)
    }

    func close() async throws {
        guard let location, _readyState.value == .open else {
            return
        }
        _readyState.value = .closing
        var request = makeRequest(location)
        request.httpMethod = "DELETE"
        request.addValue("application/sdp", forHTTPHeaderField: "Content-Type")
        _ = try await URLSession.shared.data(for: request)
        await _stream.close()
        tracks.removeAll()
        peerConnection?.close()
        self.location = nil
        _readyState.value = .closed
    }

    /// Builds a request for the WHIP/WHEP endpoint, converting URL userinfo
    /// (https://user:pass@host/…) into an HTTP Basic Authorization header.
    /// URLSession does not transmit userinfo, and MediaMTX authenticates WHIP
    /// publishing via Basic auth (query parameters are not accepted there,
    /// unlike its RTMP/HLS endpoints).
    private func makeRequest(_ url: URL) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let user = components?.user
        let password = components?.password
        components?.user = nil
        components?.password = nil
        var request = URLRequest(url: components?.url ?? url)
        if let user, !user.isEmpty {
            let credentials = Data("\(user):\(password ?? "")".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func requestOffer(_ url: URL, offer: String) async throws -> String {
        logger.debug(offer)
        var request = makeRequest(url)
        request.httpMethod = "POST"
        request.addValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        // Surface server-side rejections: upstream ignored the HTTP status and fed
        // error bodies (JSON) into setRemoteDescription, masking the real reason.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.warn("WHEP/WHIP endpoint rejected offer: HTTP \(http.statusCode) — \(body)")
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        if let response = response as? HTTPURLResponse {
            if let location = response.allHeaderFields["Location"] as? String {
                if location.hasSuffix("http") {
                    self.location = URL(string: location)
                } else {
                    var baseURL = "\(url.scheme ?? "http")://\(url.host ?? "")"
                    if let port = url.port {
                        baseURL += ":\(port)"
                    }
                    self.location = URL(string: "\(baseURL)\(location)")
                }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func makePeerConnection() throws -> RTCPeerConnection {
        let conneciton = try RTCPeerConnection(configuration)
        conneciton.delegate = self
        return conneciton
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
