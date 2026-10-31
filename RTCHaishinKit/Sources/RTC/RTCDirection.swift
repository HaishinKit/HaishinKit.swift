import libdatachannel

/// The direction of media flow relative to the local peer.
public enum RTCDirection: Sendable {
    /// The direction is unspecified.
    case unknown
    /// Send and receive media.
    case sendrecv
    /// Send media without receiving.
    case sendonly
    /// Receive media without sending.
    case recvonly
    /// Neither send nor receive media.
    case inactive

    var cValue: rtcDirection {
        switch self {
        case .unknown:
            return RTC_DIRECTION_UNKNOWN
        case .sendrecv:
            return RTC_DIRECTION_SENDRECV
        case .sendonly:
            return RTC_DIRECTION_SENDONLY
        case .recvonly:
            return RTC_DIRECTION_RECVONLY
        case .inactive:
            return RTC_DIRECTION_INACTIVE
        }
    }
}
