import Foundation

struct MoQTPublishSkipped {
    let namespaceSuffix: [Data]
    let name: Data

    init(_ payload: inout MoQTPayload) throws {
        namespaceSuffix = try payload.getNamespace()
        name = try payload.getBytes(limit: 4096)
        guard namespaceSuffix.reduce(name.count, { $0 + $1.count }) <= 4096 else {
            throw MoQTPayload.Error.invalidField
        }
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(UInt64(namespaceSuffix.count))
        for field in namespaceSuffix { payload.putBytes(field) }
        payload.putBytes(name)
        return .init(.publishSkipped, payload.data)
    }
}
