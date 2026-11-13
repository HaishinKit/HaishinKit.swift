import Foundation

struct MoQTRequestUpdate {
    let requestId: UInt64
    let parameters: MoQTMessageParameters

    init(_ payload: inout MoQTPayload) throws {
        requestId = try payload.getInt()
        parameters = try MoQTMessageParameters(&payload, allowed: [2, 3, 4, 6, 0x11, 0x20, 0x21, 0x23, 0x25, 0x26, 0x27, 0x28, 0x29, 0x32, 0x34])
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(requestId)
        parameters.encode(into: &payload)
        return .init(.requestUpdate, payload.data)
    }
}
