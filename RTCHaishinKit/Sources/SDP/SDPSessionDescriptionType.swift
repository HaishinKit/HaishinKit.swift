import libdatachannel

/// The role of an SDP description in session negotiation.
public enum SDPSessionDescriptionType: String, Sendable {
    /// An answer to a remote offer.
    case answer
    /// An offer proposing session parameters.
    case offer
    /// A provisional answer before the final answer.
    case pranswer
    /// A request to roll back a pending negotiation.
    case rollback
}
