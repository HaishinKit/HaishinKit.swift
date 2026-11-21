import Foundation

/// An authorization token sent by value in a MOQT request.
public struct MoQTAuthorizationToken: Sendable {
    /// The token type expected by the peer.
    public let type: UInt64
    /// The token payload bytes.
    public let value: Data

    /// Creates a token from its type and payload.
    ///
    /// - Parameters:
    ///   - type: The token type expected by the peer.
    ///   - value: The token payload bytes.
    public init(type: UInt64, value: Data) {
        self.type = type
        self.value = value
    }

    func encodeParameter(in body: inout MoQTPayload) {
        var token = MoQTPayload()
        token.putInt(3) // USE_VALUE
        token.putInt(type)
        token.putData(value)
        body.putInt(3) // AUTHORIZATION_TOKEN
        body.putBytes(token.data)
    }
}
