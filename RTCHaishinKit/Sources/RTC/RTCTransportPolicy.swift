import libdatachannel

/// The policy for selecting ICE transport candidates.
public enum RTCTransportPolicy: Sendable, Encodable {
    /// Allow all candidate types.
    case all
    /// Use only relay candidates.
    case relay
}

extension RTCTransportPolicy {
    var cValue: rtcTransportPolicy {
        switch self {
        case .all:
            return RTC_TRANSPORT_POLICY_ALL
        case .relay:
            return RTC_TRANSPORT_POLICY_RELAY
        }
    }
}
