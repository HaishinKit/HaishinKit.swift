import HaishinKit

/// A configuration object that defines options for an HTTPSession.
///
/// The properties of this structure are internally converted into
/// an `RTCConfiguration` and applied when creating the underlying
/// `RTCPeerConnection`.
///
public struct HTTPSessionConfiguration: StreamSessionConfiguration, RTCConfigurationConvertible {
    public var iceServers: [String] = []
    public var bindAddress: String?
    public var certificateType: RTCCertificateType?
    public var iceTransportPolicy: RTCTransportPolicy?
    public var isIceUdpMuxEnabled: Bool = false
    public var isAutoNegotionEnabled: Bool = true
    public var isForceMediaTransport: Bool = false
    public var portRange: Range<UInt16>?
    public var mtu: Int32?
    public var maxMesasgeSize: Int32?
}
