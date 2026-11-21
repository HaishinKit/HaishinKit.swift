/// A successful SUBSCRIBE_OK response.
public struct MoQTSubscribeOk: Sendable {
    /// The publisher-assigned track alias used by incoming objects.
    public let trackAlias: UInt64
    /// The advisory subscription lifetime in milliseconds. Zero or nil indicates no known expiry.
    public let expires: UInt64?
    /// The group identifier of the largest known object, if reported.
    public let largestGroupId: UInt64?
    /// The object identifier of the largest known object, if reported.
    public let largestObjectId: UInt64?
    /// The track properties supplied by the publisher.
    public let trackProperties: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        trackAlias = try payload.getInt()
        let parameters = try MoQTResponseParameters(&payload, allowsLargestObject: true)
        expires = parameters.expires
        largestGroupId = parameters.largestGroupId
        largestObjectId = parameters.largestObjectId
        trackProperties = try MoQTKeyValue.decode(&payload)
    }
}
