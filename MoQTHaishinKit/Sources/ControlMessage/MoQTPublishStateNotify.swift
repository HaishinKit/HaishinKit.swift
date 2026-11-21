import Foundation

struct MoQTPublishStateNotify {
    let parameters: MoQTMessageParameters

    init(_ payload: inout MoQTPayload) throws {
        parameters = try MoQTMessageParameters(&payload, allowed: [9, 0x11, 0x21])
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        parameters.encode(into: &payload)
        return .init(.publishStateNotify, payload.data)
    }
}
