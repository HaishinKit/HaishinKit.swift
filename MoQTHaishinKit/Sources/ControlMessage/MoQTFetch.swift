import Foundation

struct MoQTFetch {
    let requestId: UInt64
    let namespace: [Data]
    let name: Data
    let parameters: MoQTMessageParameters

    init(_ payload: inout MoQTPayload) throws {
        requestId = try payload.getInt()
        namespace = try payload.getNamespace()
        name = try payload.getBytes(limit: 4096)
        guard namespace.reduce(name.count, { $0 + $1.count }) <= 4096 else {
            throw MoQTPayload.Error.invalidField
        }
        parameters = try MoQTMessageParameters(&payload, allowed: [3, 0x0a, 0x20, 0x21, 0x22, 0x25, 0x26, 0x27, 0x28, 0x35])
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(requestId)
        payload.putInt(UInt64(namespace.count))
        for field in namespace { payload.putBytes(field) }
        payload.putBytes(name)
        parameters.encode(into: &payload)
        return .init(.fetch, payload.data)
    }
}
