import Foundation

struct MoQTPublishDone {
    let statusCode: UInt64
    let streamCount: UInt64
    let reasonPhrase: String

    init(_ payload: inout MoQTPayload) throws {
        statusCode = try payload.getInt()
        streamCount = try payload.getInt()
        reasonPhrase = try String(decoding: payload.getBytes(limit: 1024), as: UTF8.self)
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    var message: MoQTControlMessage {
        var payload = MoQTPayload()
        payload.putInt(statusCode)
        payload.putInt(streamCount)
        payload.putBytes(Data(reasonPhrase.utf8))
        return .init(.publishDone, payload.data)
    }
}
