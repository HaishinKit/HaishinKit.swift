import Foundation

/// A REQUEST_ERROR response thrown when the peer rejects a request.
public struct MoQTRequestError: Swift.Error {
    /// The peer’s MOQT request error code.
    public let code: UInt64
    /// The minimum retry delay in milliseconds, or nil when the peer advises against retrying.
    public let retryAfterMilliseconds: UInt64?
    /// The diagnostic text supplied by the peer.
    public let reasonPhrase: String
    /// The structured error details supplied by the peer.
    public let details: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        code = try payload.getInt()
        let interval = try payload.getInt()
        retryAfterMilliseconds = interval == 0 ? nil : interval - 1
        reasonPhrase = String(decoding: try payload.getBytes(limit: 1024), as: UTF8.self)
        details = try MoQTKeyValue.decode(&payload)
    }
}
