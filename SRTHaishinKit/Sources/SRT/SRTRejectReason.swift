import libsrt

/// The reason an SRT connection attempt was rejected.
///
/// The raw values correspond to the SRT library’s rejection codes.
public enum SRTRejectReason: Int, Sendable {
    /// No rejection reason is available.
    case unknown = 0
    /// A system operation failed.
    case system = 1
    /// The remote peer declined the connection.
    case peer = 2
    /// Required resources could not be allocated.
    case resource = 3
    /// The handshake contained invalid data.
    case rogue = 4
    /// The listener’s pending connection queue is full.
    case backlog = 5
    /// An internal programming error occurred.
    case ipe = 6
    /// The socket is being closed.
    case close = 7
    /// The peer’s SRT version is below the required minimum.
    case version = 8
    /// The rendezvous cookies collided.
    case rdvcookie = 9
    /// The encryption passphrase is incorrect.
    case badsecret = 10
    /// The peers disagree on whether encryption is required.
    case unsecure = 11
    /// The peers use incompatible message and stream APIs.
    case messageapi = 12
    /// The peers selected incompatible congestion controllers.
    case congestion = 13
    /// The packet filter settings are incompatible.
    case filter = 14
    /// The connection group settings are incompatible.
    case group = 15
    /// Connection setup exceeded its time limit.
    case timeout = 16
    /// The cryptographic settings conflict.
    case crypto = 17

    init?(socket: SRTSOCKET) {
        self.init(rawValue: Int(srt_getrejectreason(socket)))
    }
}
