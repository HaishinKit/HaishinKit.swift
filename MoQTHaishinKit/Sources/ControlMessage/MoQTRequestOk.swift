/// A successful REQUEST_OK response.
public struct MoQTRequestOk: Sendable {
    /// The advisory request lifetime in milliseconds. Zero or nil indicates no known expiry.
    public let expires: UInt64?

    /// The group identifier of the largest known object, if included.
    public let largestGroupId: UInt64?
    /// The object identifier of the largest known object, if included.
    public let largestObjectId: UInt64?
    /// The track properties included in the response.
    public let trackProperties: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload, includesTrackInformation: Bool = false) throws {
        let parameters = try MoQTResponseParameters(&payload, allowsLargestObject: includesTrackInformation)
        expires = parameters.expires
        largestGroupId = parameters.largestGroupId
        largestObjectId = parameters.largestObjectId
        trackProperties = includesTrackInformation ? try MoQTKeyValue.decode(&payload) : []
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }
}
