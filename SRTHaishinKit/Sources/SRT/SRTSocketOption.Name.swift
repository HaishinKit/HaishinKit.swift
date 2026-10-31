import Foundation
import libsrt

extension SRTSocketOption.Name: RawRepresentable {
    // MARK: RawRepresentable
    /// Looks up a supported option by its case-sensitive string name.
    ///
    /// - Parameter rawValue: The option name.
    /// - Returns: `nil` if the name is not recognized by this lookup.
    public init?(rawValue: String) {
        switch rawValue {
        case "bindtodevice":
            self = .bindtodevice
        case "congestion":
            self = .congestion
        case "conntimeo":
            self = .conntimeo
        case "drifttrace":
            self = .drifttracer
        case "enforcedencryption":
            self = .enforcedencryption
        case "event":
            self = .event
        case "fc":
            self = .fc
        case "groupconnect":
            self = .groupconnect
        case "groupminstabletimeo":
            self = .groupminstabletimeo
        case "grouptype":
            self = .grouptype
        case "inputbw":
            self = .inputbw
        case "iptos":
            self = .iptos
        case "ipttl":
            self = .ipttl
        case "ipv6only":
            self = .ipv6only
        case "isn":
            self = .isn
        case "kmpreannounce":
            self = .kmpreannounce
        case "kmrefreshrate":
            self = .kmrefreshrate
        case "kmstate":
            self = .kmstate
        case "latency":
            self = .latency
        case "lossmaxttl":
            self = .lossmaxttl
        case "maxbw":
            self = .maxbw
        case "messageapi":
            self = .messageapi
        case "mininputbw":
            self = .mininputbw
        case "minversion":
            self = .minversion
        case "mss":
            self = .mss
        case "nakreport":
            self = .nakreport
        case "packetfilter":
            self = .packetfilter
        case "passphrase":
            self = .passphrase
        case "pbkeylen":
            self = .pbkeylen
        case "peeridletimeo":
            self = .peeridletimeo
        case "peerlatency":
            self = .peerlatency
        case  "peerversion":
            self = .peerversion
        case "rcvsyn":
            self = .rcvsyn
        case  "rcvtimeo":
            self = .rcvtimeo
        case "rendezvous":
            self = .rendezvous
        case "retransmitalgo":
            self = .retransmitalgo
        case "reuseaddr":
            self = .reuseaddr
        case "sender":
            self = .sender
        case "sndbuf":
            self = .sndbuf
        case "snddata":
            self = .snddata
        case "snddropdelay":
            self = .snddropdelay
        case "sndkmstate":
            self = .sndkmstate
        case "sndsyn":
            self = .sndsyn
        case "sndtimeo":
            self = .sndtimeo
        case "state":
            self = .state
        case "streamid":
            self = .streamid
        case "tlpktdrop":
            self = .tlpktdrop
        case "transtype":
            self = .transtype
        case "tsbpdmode":
            self = .tsbpdmode
        case "udp_rcvbuf":
            self = .udpRcvbuf
        case "udp_sndbuf":
            self = .udpSndbuf
        case "version":
            self = .version
        default:
            return nil
        }
    }
}

// https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#list-of-options
extension SRTSocketOption.Name {
    /// The socket option corresponding to `SRTO_BINDTODEVICE`.
    public static let bindtodevice = Self(rawValue: "bindtodevice", symbol: SRTO_BINDTODEVICE, restriction: .preBind, type: .string)
    /// The socket option corresponding to `SRTO_CONGESTION`.
    public static let congestion = Self(rawValue: "congestion", symbol: SRTO_CONGESTION, restriction: .pre, type: .string)
    /// The socket option corresponding to `SRTO_CONNTIMEO`.
    public static let conntimeo = Self(rawValue: "conntimeo", symbol: SRTO_CONNTIMEO, restriction: .pre, type: .int32)
    // public static let cryptomode = Self(name: "cryptomode", symbol: SRTO_CRYPTOMODE, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_DRIFTTRACER`.
    public static let drifttracer = Self(rawValue: "drifttracer", symbol: SRTO_DRIFTTRACER, restriction: .post, type: .bool)
    /// The socket option corresponding to `SRTO_ENFORCEDENCRYPTION`.
    public static let enforcedencryption = Self(rawValue: "enforcedencryption", symbol: SRTO_ENFORCEDENCRYPTION, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_EVENT`.
    public static let event = Self(rawValue: "event", symbol: SRTO_EVENT, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_FC`.
    public static let fc = Self(rawValue: "fc", symbol: SRTO_FC, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_GROUPCONNECT`.
    public static let groupconnect = Self(rawValue: "groupconnect", symbol: SRTO_GROUPCONNECT, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_GROUPMINSTABLETIMEO`.
    public static let groupminstabletimeo = Self(rawValue: "groupminstabletimeo", symbol: SRTO_GROUPMINSTABLETIMEO, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_GROUPTYPE`.
    public static let grouptype = Self(rawValue: "grouptype", symbol: SRTO_GROUPTYPE, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_INPUTBW`.
    public static let inputbw = Self(rawValue: "inputbw", symbol: SRTO_INPUTBW, restriction: .post, type: .int64)
    /// The socket option corresponding to `SRTO_IPTOS`.
    public static let iptos = Self(rawValue: "iptos", symbol: SRTO_IPTOS, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_IPTTL`.
    public static let ipttl = Self(rawValue: "ipttl", symbol: SRTO_IPTTL, restriction: .preBind, type: .int64)
    /// The socket option corresponding to `SRTO_IPV6ONLY`.
    public static let ipv6only = Self(rawValue: "ipv6only", symbol: SRTO_IPV6ONLY, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_ISN`.
    public static let isn = Self(rawValue: "isn", symbol: SRTO_ISN, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_KMPREANNOUNCE`.
    public static let kmpreannounce = Self(rawValue: "kmpreannounce", symbol: SRTO_KMPREANNOUNCE, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_KMREFRESHRATE`.
    public static let kmrefreshrate = Self(rawValue: "kmrefreshrate", symbol: SRTO_KMREFRESHRATE, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_KMSTATE`.
    public static let kmstate = Self(rawValue: "kmstate", symbol: SRTO_KMSTATE, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_LATENCY`.
    public static let latency = Self(rawValue: "latency", symbol: SRTO_LATENCY, restriction: .pre, type: .int32)
    // public static let linger = Self(name: "linger", symbol: SRTO_LINGER, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_LOSSMAXTTL`.
    public static let lossmaxttl = Self(rawValue: "lossmaxttl", symbol: SRTO_LOSSMAXTTL, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_MAXBW`.
    public static let maxbw = Self(rawValue: "maxbw", symbol: SRTO_MAXBW, restriction: .post, type: .int64)
    // public static let maxrexmitbw = Self(name: "maxrexmitbw", symbol: SRTO_MAXREXMITBW, restriction: .post, type: .int64)
    /// The socket option corresponding to `SRTO_MESSAGEAPI`.
    public static let messageapi = Self(rawValue: "messageapi", symbol: SRTO_MESSAGEAPI, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_MININPUTBW`.
    public static let mininputbw = Self(rawValue: "mininputbw", symbol: SRTO_MININPUTBW, restriction: .pre, type: .int64)
    /// The socket option corresponding to `SRTO_MINVERSION`.
    public static let minversion = Self(rawValue: "minversion", symbol: SRTO_MINVERSION, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_MSS`.
    public static let mss = Self(rawValue: "mss", symbol: SRTO_MSS, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_NAKREPORT`.
    public static let nakreport = Self(rawValue: "nakreport", symbol: SRTO_NAKREPORT, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_OHEADBW`.
    public static let oheadbw = Self(rawValue: "oheadbw", symbol: SRTO_OHEADBW, restriction: .post, type: .int32)
    /// The socket option corresponding to `SRTO_PACKETFILTER`.
    public static let packetfilter = Self(rawValue: "packetfilter", symbol: SRTO_PACKETFILTER, restriction: .pre, type: .string)
    /// The socket option corresponding to `SRTO_PASSPHRASE`.
    public static let passphrase = Self(rawValue: "passphrase", symbol: SRTO_PASSPHRASE, restriction: .pre, type: .string)
    /// The socket option corresponding to `SRTO_PBKEYLEN`.
    public static let pbkeylen = Self(rawValue: "pbkeylen", symbol: SRTO_PBKEYLEN, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_PEERIDLETIMEO`.
    public static let peeridletimeo = Self(rawValue: "peeridletimeo", symbol: SRTO_PEERIDLETIMEO, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_PEERLATENCY`.
    public static let peerlatency = Self(rawValue: "peerlatency", symbol: SRTO_PEERLATENCY, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_PEERVERSION`.
    public static let peerversion = Self(rawValue: "peerversion", symbol: SRTO_PEERVERSION, restriction: .pre, type: .string)
    /// The socket option corresponding to `SRTO_RCVBUF`.
    public static let rcvbuf = Self(rawValue: "rcvbuf", symbol: SRTO_RCVBUF, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_RCVDATA`.
    public static let rcvdata = Self(rawValue: "rcvdata", symbol: SRTO_RCVDATA, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_RCVLATENCY`.
    public static let rcvlatency = Self(rawValue: "rcvlatency", symbol: SRTO_RCVLATENCY, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_RCVSYN`.
    public static let rcvsyn = Self(rawValue: "rcvsyn", symbol: SRTO_RCVSYN, restriction: .post, type: .bool)
    /// The socket option corresponding to `SRTO_RCVTIMEO`.
    public static let rcvtimeo = Self(rawValue: "rcvtimeo", symbol: SRTO_RCVTIMEO, restriction: .post, type: .int32)
    /// The socket option corresponding to `SRTO_RENDEZVOUS`.
    public static let rendezvous = Self(rawValue: "rendezvous", symbol: SRTO_RENDEZVOUS, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_RETRANSMITALGO`.
    public static let retransmitalgo = Self(rawValue: "retransmitalgo", symbol: SRTO_RETRANSMITALGO, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_REUSEADDR`.
    public static let reuseaddr = Self(rawValue: "reuseaddr", symbol: SRTO_REUSEADDR, restriction: .preBind, type: .bool)
    /// The socket option corresponding to `SRTO_SENDER`.
    public static let sender = Self(rawValue: "sender", symbol: SRTO_SENDER, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_SNDBUF`.
    public static let sndbuf = Self(rawValue: "sndbuf", symbol: SRTO_SNDBUF, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_SNDDATA`.
    public static let snddata = Self(rawValue: "snddata", symbol: SRTO_SNDDATA, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_SNDDROPDELAY`.
    public static let snddropdelay = Self(rawValue: "snddropdelay", symbol: SRTO_SNDDROPDELAY, restriction: .post, type: .int32)
    /// The socket option corresponding to `SRTO_SNDKMSTATE`.
    public static let sndkmstate = Self(rawValue: "sndkmstate", symbol: SRTO_SNDKMSTATE, restriction: .post, type: .int32)
    /// The socket option corresponding to `SRTO_SNDSYN`.
    public static let sndsyn = Self(rawValue: "sndsyn", symbol: SRTO_SNDSYN, restriction: .post, type: .bool)
    /// The socket option corresponding to `SRTO_SNDTIMEO`.
    public static let sndtimeo = Self(rawValue: "sndtimeo", symbol: SRTO_SNDTIMEO, restriction: .post, type: .int32)
    /// The socket option corresponding to `SRTO_STATE`.
    public static let state = Self(rawValue: "state", symbol: SRTO_STATE, restriction: .none, type: .int32)
    /// The socket option corresponding to `SRTO_STREAMID`.
    public static let streamid = Self(rawValue: "streamid", symbol: SRTO_STREAMID, restriction: .pre, type: .string)
    /// The socket option corresponding to `SRTO_TLPKTDROP`.
    public static let tlpktdrop = Self(rawValue: "tlpktdrop", symbol: SRTO_TLPKTDROP, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_TRANSTYPE`.
    public static let transtype = Self(rawValue: "transtype", symbol: SRTO_TRANSTYPE, restriction: .pre, type: .int32)
    /// The socket option corresponding to `SRTO_TSBPDMODE`.
    public static let tsbpdmode = Self(rawValue: "tsbpdmode", symbol: SRTO_TSBPDMODE, restriction: .pre, type: .bool)
    /// The socket option corresponding to `SRTO_UDP_RCVBUF`.
    public static let udpRcvbuf = Self(rawValue: "udp_rcvbuf", symbol: SRTO_UDP_RCVBUF, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_UDP_SNDBUF`.
    public static let udpSndbuf = Self(rawValue: "udp_sndbuf", symbol: SRTO_UDP_SNDBUF, restriction: .preBind, type: .int32)
    /// The socket option corresponding to `SRTO_VERSION`.
    public static let version = Self(rawValue: "version", symbol: SRTO_VERSION, restriction: .none, type: .int32)
}
