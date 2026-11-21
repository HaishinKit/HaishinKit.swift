/// A peer notification that a session or request should migrate.
public struct MoQTGoAway: Sendable {
    /// The URI for the replacement session, or nil to reuse the current URI.
    public let newSessionURI: String?
    /// The peer’s grace period in milliseconds, or zero if unspecified.
    public let timeoutMilliseconds: UInt64

    init(_ body: inout MoQTPayload) throws {
        let uri = try body.getBytes(limit: 8192)
        newSessionURI = uri.isEmpty ? nil : String(decoding: uri, as: UTF8.self)
        timeoutMilliseconds = try body.getInt()
        guard body.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }
}
