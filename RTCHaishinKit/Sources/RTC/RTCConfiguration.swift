import Foundation
import libdatachannel

/// Settings used to create an underlying WebRTC peer connection.
public protocol RTCConfigurationConvertible: Sendable {
    /// The ICE server URLs used to establish the connection.
    var iceServers: [String] { get }
    /// The local IP address to bind to, or `nil` to leave address selection to the library.
    var bindAddress: String? { get }
    /// The certificate type used for DTLS, or `nil` to use the library default.
    var certificateType: RTCCertificateType? { get }
    /// The policy for selecting ICE candidates, or `nil` to use the library default.
    var iceTransportPolicy: RTCTransportPolicy? { get }
    /// A Boolean value that enables ICE UDP multiplexing.
    var isIceUdpMuxEnabled: Bool { get }
    /// A Boolean value that enables automatic negotiation.
    var isAutoNegotionEnabled: Bool { get }
    /// A Boolean value that forces media transport even when no media tracks are present.
    var isForceMediaTransport: Bool { get }
    /// The port range supplied to the ICE implementation, or `nil` for automatic allocation.
    var portRange: Range<UInt16>? { get }
    /// The maximum transmission unit, in bytes, or `nil` for automatic selection.
    var mtu: Int32? { get }
    /// The maximum data channel message size, in bytes, or `nil` to use the library default.
    var maxMesasgeSize: Int32? { get }
}

extension RTCConfigurationConvertible {
    func createPeerConnection() -> Int32 {
        return iceServers.withCStringArray { cIceServers in
            return [bindAddress ?? ""].withCStrings { cStrings in
                var config = rtcConfiguration()
                if !iceServers.isEmpty {
                    config.iceServers = cIceServers
                    config.iceServersCount = Int32(iceServers.count)
                }
                if bindAddress != nil {
                    config.bindAddress = cStrings[0]
                }
                if let certificateType {
                    config.certificateType = certificateType.cValue
                }
                if let iceTransportPolicy {
                    config.iceTransportPolicy = iceTransportPolicy.cValue
                }
                config.enableIceUdpMux = isIceUdpMuxEnabled
                config.disableAutoNegotiation = !isAutoNegotionEnabled
                config.forceMediaTransport = isForceMediaTransport
                if let portRange {
                    config.portRangeBegin = portRange.lowerBound
                    config.portRangeEnd = portRange.upperBound
                }
                if let mtu {
                    config.mtu = mtu
                }
                if let maxMesasgeSize {
                    config.maxMessageSize = maxMesasgeSize
                }
                return rtcCreatePeerConnection(&config)
            }
        }
    }
}

/// An immutable set of WebRTC peer connection settings.
public struct RTCConfiguration: RTCConfigurationConvertible {
    static let empty = RTCConfiguration()

    /// The ICE server URLs used to establish the connection.
    public let iceServers: [String]
    /// The local IP address to bind to, or `nil` to leave address selection to the library.
    public let bindAddress: String?
    /// The certificate type used for DTLS, or `nil` to use the library default.
    public let certificateType: RTCCertificateType?
    /// The policy for selecting ICE candidates, or `nil` to use the library default.
    public let iceTransportPolicy: RTCTransportPolicy?
    /// A Boolean value that enables ICE UDP multiplexing.
    public let isIceUdpMuxEnabled: Bool
    /// A Boolean value that enables automatic negotiation.
    public let isAutoNegotionEnabled: Bool
    /// A Boolean value that forces media transport even when no media tracks are present.
    public let isForceMediaTransport: Bool
    /// The port range supplied to the ICE implementation, or `nil` for automatic allocation.
    public let portRange: Range<UInt16>?
    /// The maximum transmission unit, in bytes, or `nil` for automatic selection.
    public let mtu: Int32?
    /// The maximum data channel message size, in bytes, or `nil` to use the library default.
    public let maxMesasgeSize: Int32?

    /// Creates peer connection settings.
    ///
    /// Optional values left as `nil` use the underlying library’s defaults.
    ///
    /// - Parameters:
    ///   - iceServers: The ICE server URLs.
    ///   - bindAddress: The local IP address to bind to.
    ///   - certificateType: The DTLS certificate type.
    ///   - iceTransportPolicy: The ICE candidate policy.
    ///   - isIceUdpMuxEnabled: Whether to enable ICE UDP multiplexing.
    ///   - isAutoNegotionEnabled: Whether negotiation is automatic.
    ///   - isForceMediaTransport: Whether to create media transport even without tracks.
    ///   - portRange: The port range supplied to ICE.
    ///   - mtu: The maximum transmission unit, in bytes.
    ///   - maxMesasgeSize: The maximum data channel message size, in bytes.
    public init(
        iceServers: [String] = [],
        bindAddress: String? = nil,
        certificateType: RTCCertificateType? = nil,
        iceTransportPolicy: RTCTransportPolicy? = nil,
        isIceUdpMuxEnabled: Bool = false,
        isAutoNegotionEnabled: Bool = true,
        isForceMediaTransport: Bool = false,
        portRange: Range<UInt16>? = nil,
        mtu: Int32? = nil,
        maxMesasgeSize: Int32? = nil
    ) {
        self.iceServers = iceServers
        self.bindAddress = bindAddress
        self.certificateType = certificateType
        self.iceTransportPolicy = iceTransportPolicy
        self.isIceUdpMuxEnabled = isIceUdpMuxEnabled
        self.isAutoNegotionEnabled = isAutoNegotionEnabled
        self.isForceMediaTransport = isForceMediaTransport
        self.portRange = portRange
        self.mtu = mtu
        self.maxMesasgeSize = maxMesasgeSize
    }
}
