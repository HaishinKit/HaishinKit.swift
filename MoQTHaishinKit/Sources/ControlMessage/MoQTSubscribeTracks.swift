import Foundation

struct MoQTSubscribeTracks {
    let requestId: UInt64
    let namespacePrefix: [Data]
    let parameters: MoQTMessageParameters

    init(_ payload: inout MoQTPayload) throws {
        requestId = try payload.getInt()
        namespacePrefix = try payload.getNamespace()
        parameters = try MoQTMessageParameters(&payload, allowed: [2, 3, 6, 0x11, 0x20, 0x21, 0x22, 0x23, 0x25, 0x26, 0x27, 0x28, 0x29, 0x35])
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(requestId)
        payload.putInt(UInt64(namespacePrefix.count))
        for field in namespacePrefix { payload.putBytes(field) }
        parameters.encode(into: &payload)
        return .init(.subscribeTracks, payload.data)
    }
}
