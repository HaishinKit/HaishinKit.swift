import Foundation

struct MoQTPublish {
    let requestId: UInt64
    let namespace: [Data]
    let name: Data
    let trackAlias: UInt64
    let parameters: MoQTMessageParameters
    let trackProperties: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        requestId = try payload.getInt()
        namespace = try payload.getNamespace()
        name = try payload.getBytes(limit: 4096)
        guard namespace.reduce(name.count, { $0 + $1.count }) <= 4096 else {
            throw MoQTPayload.Error.invalidField
        }
        trackAlias = try payload.getInt()
        parameters = try MoQTMessageParameters(&payload, allowed: [2, 3, 6, 8, 9, 0x11, 0x20, 0x21, 0x22, 0x23, 0x36])
        trackProperties = try MoQTKeyValue.decode(&payload)
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(requestId)
        payload.putInt(UInt64(namespace.count))
        for field in namespace { payload.putBytes(field) }
        payload.putBytes(name)
        payload.putInt(trackAlias)
        parameters.encode(into: &payload)
        MoQTKeyValue.encode(trackProperties, into: &payload)
        return .init(.publish, payload.data)
    }
}
