import Foundation
import libdatachannel

/// A delegate that receives peer connection state changes, data channels, and ICE candidates.
public protocol RTCPeerConnectionDelegate: AnyObject {
    /// Notifies the delegate that the overall connection state changed.
    func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState)
    /// Notifies the delegate that the ICE candidate gathering state changed.
    func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState)
    /// Notifies the delegate that the ICE connection state changed.
    func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState)
    /// Notifies the delegate that the SDP signaling state changed.
    func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState)
    /// Delivers a data channel created by the remote peer.
    ///
    /// Assign its delegate to receive messages and channel state changes.
    func peerConnection(_ peerConneciton: RTCPeerConnection, didOpen dataChannel: RTCDataChannel)
    /// Delivers a newly generated local ICE candidate.
    func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate)
}

/// Manages WebRTC negotiation, media tracks, and data channels using libdatachannel.
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

    static let videoMediaDescription = """
m=video 9 UDP/TLS/RTP/SAVPF 98
a=mid:1
a=recvonly
a=rtpmap:98 H264/90000
a=rtcp-fb:98 goog-remb
a=rtcp-fb:98 nack
a=rtcp-fb:98 nack pli
a=fmtp:98 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f
"""

    static let bufferSize: Int = 1024 * 16

    /// The delegate that receives connection events.
    public weak var delegate: (any RTCPeerConnectionDelegate)?
    /// The current overall connection state.
    public private(set) var connectionState: ConnectionState = .new {
        didSet {
            guard connectionState != oldValue else {
                return
            }
            delegate?.peerConnection(self, connectionStateChanged: connectionState)
        }
    }
    /// The current ICE connection state.
    public private(set) var iceConnectionState: IceConnectionState = .new {
        didSet {
            guard iceConnectionState != oldValue else {
                return
            }
            delegate?.peerConnection(self, iceConnectionStateChanged: iceConnectionState)
        }
    }
    /// The current ICE candidate gathering state.
    public private(set) var iceGatheringState: IceGatheringState = .new {
        didSet {
            guard iceGatheringState != oldValue else {
                return
            }
            delegate?.peerConnection(self, iceGatheringStateChanged: iceGatheringState)
        }
    }
    /// The current SDP signaling state.
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

    /// Creates a peer connection and registers its event callbacks.
    ///
    /// - Parameter config: The connection settings, or `nil` to use the default configuration.
    /// - Throws: `RTCError` if connection creation or callback registration fails.
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

    /// Adds an audio or video track and schedules its association with a stream.
    ///
    /// Only `AudioStreamTrack` and `VideoStreamTrack` are handled; other conforming
    /// types are ignored. Track association with the stream runs asynchronously.
    ///
    /// - Parameters:
    ///   - track: The track descriptor and its codec settings.
    ///   - stream: The stream that will provide media for the track.
    /// - Throws: `RTCError` if the underlying track cannot be added.
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

    /// Applies a remote session description.
    ///
    /// - Parameters:
    ///   - sdp: The remote peer’s SDP text.
    ///   - type: The description type.
    /// - Throws: `RTCError` if the library rejects the description.
    public func setRemoteDesciption(_ sdp: String, type: SDPSessionDescriptionType) throws {
        logger.debug(sdp, type.rawValue)
        try RTCError.check([sdp, type.rawValue].withCStrings { cStrings in
            rtcSetRemoteDescription(connection, cStrings[0], cStrings[1])
        })
    }

    /// Requests a local session description of the specified type.
    ///
    /// - Parameter type: The description type to set.
    /// - Throws: `RTCError` if the library cannot set the description.
    public func setLocalDesciption(_ type: SDPSessionDescriptionType) throws {
        logger.debug(type.rawValue)
        try RTCError.check([type.rawValue].withCStrings { cStrings in
            rtcSetLocalDescription(connection, cStrings[0])
        })
    }

    /// Generates an SDP offer for signaling.
    ///
    /// - Returns: The offer as SDP text.
    /// - Throws: `RTCError` if the offer cannot be generated or retrieved.
    public func createOffer() throws -> String {
        return try CUtil.getString { buffer, size in
            rtcCreateOffer(connection, buffer, size)
        }
    }

    /// Generates an SDP answer for signaling.
    ///
    /// - Returns: The answer as SDP text.
    /// - Throws: `RTCError` if the answer cannot be generated or retrieved.
    public func createAnswer() throws -> String {
        return try CUtil.getString { buffer, size in
            rtcCreateAnswer(connection, buffer, size)
        }
    }

    /// Creates a data channel with the specified label.
    ///
    /// - Parameter label: The channel’s application-defined name.
    /// - Returns: A channel whose delegate can receive state changes and messages.
    /// - Throws: `RTCError` if creation or callback registration fails.
    public func createDataChannel(_ label: String) throws -> RTCDataChannel {
        let result = try RTCError.check([label].withCStrings { cStrings in
            rtcCreateDataChannel(connection, cStrings[0])
        })
        return try RTCDataChannel(id: result)
    }

    /// Closes the underlying peer connection. Errors are written to the log.
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
