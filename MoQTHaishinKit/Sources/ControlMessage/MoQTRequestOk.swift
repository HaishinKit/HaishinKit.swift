/// A successful REQUEST_OK response.
public struct MoQTRequestOk: Sendable {
    /// The advisory request lifetime in milliseconds. Zero or nil indicates no known expiry.
    public let expires: UInt64?

    init(_ payload: inout MoQTPayload) throws {
        let parameters = try MoQTResponseParameters(&payload, allowsLargestObject: false)
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
        expires = parameters.expires
    }
}
