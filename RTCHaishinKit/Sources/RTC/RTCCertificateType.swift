import libdatachannel

/// The certificate algorithm used for a WebRTC connection.
public enum RTCCertificateType: Sendable, Encodable {
    /// Use the underlying library’s default certificate type.
    case `default`
    /// Use an ECDSA certificate.
    case ECDSA
    /// Use an RSA certificate.
    case RSA
}

extension RTCCertificateType {
    var cValue: rtcCertificateType {
        switch self {
        case .default:
            return RTC_CERTIFICATE_DEFAULT
        case .ECDSA:
            return RTC_CERTIFICATE_ECDSA
        case .RSA:
            return RTC_CERTIFICATE_RSA
        }
    }
}
