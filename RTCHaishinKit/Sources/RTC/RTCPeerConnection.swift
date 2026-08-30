import Foundation
import libdatachannel

public protocol RTCPeerConnectionDelegate: AnyObject {
    func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState)
    func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState)
    func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState)
    func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState)
    func peerConnection(_ peerConneciton: RTCPeerConnection, didOpen dataChannel: RTCDataChannel)
    func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate)
}

public final class RTCPeerConnection {
    /// Represents the state of a connection.
    public enum ConnectionState: Sendable {
        /// The connection has been created, but no connection attempt has started yet.
        case new
        /// A connection attempt is currently in progress.
        case connecting
        /// The connection has been successfully established.
        case connected
        /// The connection was previously established but is now temporarily lost.
        case disconnected
        /// The connection has encountered an unrecoverable error.
        case failed
        /// The connection has been closed and will not be used again.
        case closed
    }

    /// Represents the ICE gathering state of an RTCPeerConnection.
    public enum IceGatheringState: Sendable {
        /// ICE gathering has not yet started.
        case new
        /// The agent is currently gathering ICE candidates.
        case inProgress
        /// ICE gathering has finished. No more candidates will be gathered.
        case complete
    }

    /// Represents the state of the ICE connection for an RTCPeerConnection.
    public enum IceConnectionState: Sendable {
        /// The ICE agent is newly created and no checks have started yet.
        case new
        /// The ICE agent is checking candidate pairs to find a workable connection.
        case checking
        /// A usable ICE connection has been established.
        case connected
        /// ICE checks have completed successfully, and the connection is fully stable.
        case completed
        /// The ICE connection has failed and cannot recover.
        case failed
        /// The ICE connection has been lost or interrupted.
        case disconnected
        /// The ICE agent has been closed and will not be used again.
        case closed
    }

    /// Represents the signaling state of an RTCPeerConnection.
    public enum SignalingState: Sendable {
        /// The signaling state is stable; there is no outstanding local or remote offer.
        case stable
        /// A local offer has been created and set as the local description.
        case haveLocalOffer
        /// A remote offer has been received and set as the remote description.
        case haveRemoteOffer
        /// A provisional (pr-answer) has been set as the local description.
        case haveLocalPRAnswer
        /// A provisional (pr-answer) has been set as the remote description.
        case haveRemotePRAnswer
    }

    static let audioMediaDescription = """
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=mid:0
a=recvonly
a=rtpmap:111 opus/48000/2
a=fmtp:111 minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1
"""

    // Offer MULTIPLE H264 profile variants like a browser does. MediaMTX/Pion
    // matches profile-level-id's profile bytes strictly; a single hardcoded
    // 42e01f offer is rejected ("codecs not supported by client") whenever the
    // published stream is plain/constrained baseline (42001f/42c01f), main
    // (4d001f) or high (64001f) — i.e. most drones and third-party encoders.
    // The server's answer picks exactly one payload; the depacketizer follows
    // the negotiated description, so extra variants are harmless.
    static let videoMediaDescription = """
m=video 9 UDP/TLS/RTP/SAVPF 98 99 100 101 102
a=mid:1
a=recvonly
a=rtpmap:98 H264/90000
a=rtcp-fb:98 goog-remb
a=rtcp-fb:98 nack
a=rtcp-fb:98 nack pli
a=fmtp:98 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f
a=rtpmap:99 H264/90000
a=rtcp-fb:99 goog-remb
a=rtcp-fb:99 nack
a=rtcp-fb:99 nack pli
a=fmtp:99 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42c01f
a=rtpmap:100 H264/90000
a=rtcp-fb:100 goog-remb
a=rtcp-fb:100 nack
a=rtcp-fb:100 nack pli
a=fmtp:100 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f
a=rtpmap:101 H264/90000
a=rtcp-fb:101 goog-remb
a=rtcp-fb:101 nack
a=rtcp-fb:101 nack pli
a=fmtp:101 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f
a=rtpmap:102 H264/90000
a=rtcp-fb:102 goog-remb
a=rtcp-fb:102 nack
a=rtcp-fb:102 nack pli
a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f
"""

    static let bufferSize: Int = 1024 * 16

    /// Specifies the delegate of an RTCPeerConnection.
    public weak var delegate: (any RTCPeerConnectionDelegate)?
    /// The current state of connection.
    public private(set) var connectionState: ConnectionState = .new {
        didSet {
            guard connectionState != oldValue else {
                return
            }
            delegate?.peerConnection(self, connectionStateChanged: connectionState)
        }
    }
    /// The current state of ice connection.
    public private(set) var iceConnectionState: IceConnectionState = .new {
        didSet {
            guard iceConnectionState != oldValue else {
                return
            }
            delegate?.peerConnection(self, iceConnectionStateChanged: iceConnectionState)
        }
    }
    /// The current state of ice gathering.
    public private(set) var iceGatheringState: IceGatheringState = .new {
        didSet {
            guard iceGatheringState != oldValue else {
                return
            }
            delegate?.peerConnection(self, iceGatheringStateChanged: iceGatheringState)
        }
    }
    /// The current state of signaling.
    public private(set) var signalingState: SignalingState = .stable {
        didSet {
            guard signalingState != oldValue else {
                return
            }
            delegate?.peerConnection(self, signalingStateChanged: signalingState)
        }
    }
    private let connection: Int32
    private(set) var localDescription: String = ""

    /// Creates a peerConnection instance.
    public init(_ config: (some RTCConfigurationConvertible)? = nil) throws {
        if let config {
            connection = config.createPeerConnection()
        } else {
            connection = RTCConfiguration.empty.createPeerConnection()
        }
        try RTCError.check(connection)
        do {
            try RTCError.check(rtcSetLocalDescriptionCallback(connection) { _, sdp, _, pointer in
                guard let pointer else { return }
                if let sdp {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().localDescription = String(cString: sdp)
                }
            })
            try RTCError.check(rtcSetLocalCandidateCallback(connection) { _, candidate, mid, pointer in
                guard let pointer else { return }
                Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().didGenerateCandidate(.init(
                    candidate: candidate,
                    mid: mid
                ))
            })
            try RTCError.check(rtcSetStateChangeCallback(connection) { _, state, pointer in
                guard let pointer else { return }
                if let state = ConnectionState(cValue: state) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().connectionState = state
                }
            })
            try RTCError.check(rtcSetIceStateChangeCallback(connection) { _, state, pointer in
                guard let pointer else { return }
                if let state = IceConnectionState(cValue: state) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().iceConnectionState = state
                }
            })
            try RTCError.check(rtcSetGatheringStateChangeCallback(connection) { _, gatheringState, pointer in
                guard let pointer else { return }
                if let gatheringState = IceGatheringState(cValue: gatheringState) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().iceGatheringState = gatheringState
                }
            })
            try RTCError.check(rtcSetSignalingStateChangeCallback(connection) { _, signalingState, pointer in
                guard let pointer else { return }
                if let signalingState = SignalingState(cValue: signalingState) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().signalingState = signalingState
                }
            })
            try RTCError.check(rtcSetTrackCallback(connection) { _, track, pointer in
                guard let pointer else { return }
                if let track = try? RTCTrack(id: track) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().didOpenTrack(track)
                }
            })
            try RTCError.check(rtcSetDataChannelCallback(connection) { _, dataChannel, pointer in
                guard let pointer else { return }
                if let channel = try? RTCDataChannel(id: dataChannel) {
                    Unmanaged<RTCPeerConnection>.fromOpaque(pointer).takeUnretainedValue().didOpenDataChannel(channel)
                }
            })
            rtcSetUserPointer(connection, Unmanaged.passUnretained(self).toOpaque())
        } catch {
            rtcDeletePeerConnection(connection)
            throw error
        }
    }

    deinit {
        close()
        rtcDeletePeerConnection(connection)
    }

    /// Adds a `MediaStreamTrack` to the peer connection and associates it with the given `MediaStream`.
    ///
    /// - Parameters:
    ///   - track: The media track to add (audio or video).
    ///   - stream: The `MediaStream` that the track belongs to.
    public func addTrack(_ track: some RTCStreamTrack, stream: RTCStream) throws {
        let msid = stream.id
        switch track {
        case let track as AudioStreamTrack:
            let config = RTCTrackConfiguration(mid: "0", streamId: msid, audioCodecSettings: track.settings)
            let id = try config.addTrack(connection, direction: .sendrecv)
            Task {
                await stream.addTrack(try RTCSendableStreamTrack(id, id: track.id))
            }
        case let track as VideoStreamTrack:
            let config = RTCTrackConfiguration(mid: "1", streamId: msid, videoCodecSettings: track.settings)
            let id = try config.addTrack(connection, direction: .sendrecv)
            Task {
                await stream.addTrack(try RTCSendableStreamTrack(id, id: track.id))
            }
        default:
            break
        }
    }

    @discardableResult
    func addTrack(_ kind: RTCStreamKind, stream: RTCStream) throws -> RTCTrack {
        let sdp: String
        switch kind {
        case .audio:
            sdp = Self.audioMediaDescription
        case .video:
            sdp = Self.videoMediaDescription
        }
        let result = try RTCError.check(sdp.withCString { cString in
            rtcAddTrack(connection, cString)
        })
        let track = try RTCTrack(id: result)
        track.delegate = stream
        return track
    }

    public func setRemoteDesciption(_ sdp: String, type: SDPSessionDescriptionType) throws {
        logger.debug(sdp, type.rawValue)
        try RTCError.check([sdp, type.rawValue].withCStrings { cStrings in
            rtcSetRemoteDescription(connection, cStrings[0], cStrings[1])
        })
    }

    public func setLocalDesciption(_ type: SDPSessionDescriptionType) throws {
        logger.debug(type.rawValue)
        try RTCError.check([type.rawValue].withCStrings { cStrings in
            rtcSetLocalDescription(connection, cStrings[0])
        })
    }

    public func createOffer() throws -> String {
        return try CUtil.getString { buffer, size in
            rtcCreateOffer(connection, buffer, size)
        }
    }

    /// Returns the CURRENT local description via rtcGetLocalDescription — unlike
    /// `createOffer()` (which requires disableAutoNegotiation and returns
    /// RTC_ERR_FAILURE otherwise), this works with auto-negotiation and, when read
    /// after ICE gathering completes, includes the gathered candidates (vanilla ICE).
    public func currentLocalDescription() throws -> String {
        return try CUtil.getString { buffer, size in
            rtcGetLocalDescription(connection, buffer, size)
        }
    }

    public func createAnswer() throws -> String {
        return try CUtil.getString { buffer, size in
            rtcCreateAnswer(connection, buffer, size)
        }
    }

    public func createDataChannel(_ label: String) throws -> RTCDataChannel {
        let result = try RTCError.check([label].withCStrings { cStrings in
            rtcCreateDataChannel(connection, cStrings[0])
        })
        return try RTCDataChannel(id: result)
    }

    public func close() {
        do {
            try RTCError.check(rtcClosePeerConnection(connection))
        } catch {
            logger.warn(error)
        }
    }

    private func didGenerateCandidate(_ candidated: RTCIceCandidate) {
        delegate?.peerConnection(self, gotIceCandidate: candidated)
    }

    private func didOpenTrack(_ track: RTCTrack) {
        logger.info(track)
    }

    private func didOpenDataChannel(_ dataChannel: RTCDataChannel) {
        delegate?.peerConnection(self, didOpen: dataChannel)
    }
}

extension RTCPeerConnection.ConnectionState {
    init?(cValue: rtcState) {
        switch cValue {
        case RTC_NEW:
            self = .new
        case RTC_CONNECTING:
            self = .connecting
        case RTC_CONNECTED:
            self = .connected
        case RTC_DISCONNECTED:
            self = .disconnected
        case RTC_FAILED:
            self = .failed
        case RTC_CLOSED:
            self = .closed
        default:
            return nil
        }
    }
}

extension RTCPeerConnection.IceGatheringState {
    init?(cValue: rtcGatheringState) {
        switch cValue {
        case RTC_GATHERING_NEW:
            self = .new
        case RTC_GATHERING_INPROGRESS:
            self = .inProgress
        case RTC_GATHERING_COMPLETE:
            self = .complete
        default:
            return nil
        }
    }
}

extension RTCPeerConnection.IceConnectionState {
    init?(cValue: rtcIceState) {
        switch cValue {
        case RTC_ICE_NEW:
            self = .new
        case RTC_ICE_CHECKING:
            self = .checking
        case RTC_ICE_CONNECTED:
            self = .connected
        case RTC_ICE_COMPLETED:
            self = .completed
        case RTC_ICE_FAILED:
            self = .failed
        case RTC_ICE_DISCONNECTED:
            self = .disconnected
        case RTC_ICE_CLOSED:
            self = .closed
        default:
            return nil
        }
    }
}

extension RTCPeerConnection.SignalingState {
    init?(cValue: rtcSignalingState) {
        switch cValue {
        case RTC_SIGNALING_STABLE:
            self = .stable
        case RTC_SIGNALING_HAVE_LOCAL_OFFER:
            self = .haveLocalOffer
        case RTC_SIGNALING_HAVE_REMOTE_OFFER:
            self = .haveRemoteOffer
        case RTC_SIGNALING_HAVE_LOCAL_PRANSWER:
            self = .haveLocalPRAnswer
        case RTC_SIGNALING_HAVE_REMOTE_PRANSWER:
            self = .haveRemotePRAnswer
        default:
            return nil
        }
    }
}
