import HaishinKit

/// Peer connection settings for a session created by `HTTPSessionFactory`.
///
/// These values are applied when the session creates its `RTCPeerConnection`.
public struct HTTPSessionConfiguration: StreamSessionConfiguration, RTCConfigurationConvertible {
    /// The ICE server URLs used to establish the connection.
    public var iceServers: [String] = []
    /// The local IP address to bind to, or `nil` to leave address selection to the library.
    public var bindAddress: String?
    /// The certificate type used for DTLS, or `nil` to use the library default.
    public var certificateType: RTCCertificateType?
    /// The policy for selecting ICE candidates, or `nil` to use the library default.
    public var iceTransportPolicy: RTCTransportPolicy?
    /// A Boolean value that enables ICE UDP multiplexing.
    public var isIceUdpMuxEnabled: Bool = false
    /// A Boolean value that enables automatic negotiation.
    public var isAutoNegotionEnabled: Bool = true
    /// A Boolean value that forces media transport even when no media tracks are present.
    public var isForceMediaTransport: Bool = false
    /// The port range supplied to the ICE implementation, or `nil` for automatic allocation.
    public var portRange: Range<UInt16>?
    /// The maximum transmission unit, in bytes, or `nil` for automatic selection.
    public var mtu: Int32?
    /// The maximum data channel message size, in bytes, or `nil` to use the library default.
    public var maxMesasgeSize: Int32?
}
