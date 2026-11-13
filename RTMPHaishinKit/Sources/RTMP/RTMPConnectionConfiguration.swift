import Foundation
import HaishinKit
import Network

/// The settings an RTMPConnection is created with.
///
/// Every property starts at the value the RTMPConnection initializer uses by default, so a configuration changes only
/// what it sets.
///
/// ## Example code:
/// ```swift
/// var configuration = RTMPConnectionConfiguration()
/// configuration.requiredInterfaceType = .cellular
/// let connection = RTMPConnection(configuration: configuration)
/// ```
public struct RTMPConnectionConfiguration: Sendable {
    /// The URL of .swf.
    public var swfUrl: String?
    /// The URL of an HTTP referer.
    public var pageUrl: String?
    /// The name of application.
    public var flashVer: String = RTMPConnection.defaultFlashVer
    /// The fourCcList for Enhancing NetConnection connect Command.
    public var fourCcList: [String]? = RTMPConnection.supportedFourCcList
    /// The video fourCc information for Enhancing NetConnection connect Command.
    public var videoFourCcInfoMap: AMFObject? = RTMPConnection.supportedVideoFourCcInfoMap
    /// The audio fourCc information for Enhancing NetConnection connect Command.
    public var audioFourCcInfoMap: AMFObject? = RTMPConnection.supportedAudioFourCcInfoMap
    /// The capability flags for Enhancing NetConnection connect Command.
    public var capsEx: Int = 0
    /// The time to wait for TCP/IP Handshake done.
    public var timeout: Int = RTMPConnection.defaultTimeout
    /// The RTMP request timeout value.
    public var requestTimeout: UInt64 = RTMPConnection.defaultRequestTimeout
    /// The outgoing RTMPChunkSize.
    public var chunkSize: Int = RTMPConnection.defaultChunkSizeS
    /// The dispatchQos for socket.
    public var qualityOfService: DispatchQoS = .userInitiated
    /// The network interface type the socket must use, such as `.wifi` or `.cellular`.
    ///
    /// The default value is nil: the system chooses the route. A device that has both Wi-Fi and cellular uses Wi-Fi by
    /// default; `.cellular` publishes over mobile data while the Wi-Fi stays available to other connections.
    public var requiredInterfaceType: NWInterface.InterfaceType?

    /// Creates a configuration with the default values.
    public init() {
    }
}
