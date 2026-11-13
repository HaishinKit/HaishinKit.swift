import Foundation

/// The SETUP message received from the peer.
public struct MoQTSetup: Sendable {
    /// The peer’s setup options.
    public let options: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        options = try MoQTKeyValue.decode(&payload)
        guard !options.contains(where: { $0.type == 1 || $0.type == 5 }) else {
            throw MoQTPayload.Error.invalidField
        }
    }

    static func clientMessage(authority: String, path: String) -> MoQTControlMessage {
        var body = MoQTPayload()
        body.putInt(1) // PATH
        body.putBytes(Data(path.utf8))
        body.putInt(4) // AUTHORITY (type 5, delta 4)
        body.putBytes(Data(authority.utf8))
        return .init(.setup, body.data)
    }
}
