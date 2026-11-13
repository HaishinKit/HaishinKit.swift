import Foundation

enum MoQTMessageType: UInt64 {
    case setup = 0x2f00
    case goaway = 0x10
    case subscribe = 0x03
    case subscribeOK = 0x04
    case requestError = 0x05
    case publishNamespace = 0x06
    case requestOK = 0x07
    case namespace = 0x08
    case namespaceDone = 0x0e
    case publishDone = 0x0b
    case subscribeNamespace = 0x50
}

struct MoQTControlMessage {
    let type: UInt64
    let body: Data

    init(_ type: MoQTMessageType, _ body: Data) {
        self.type = type.rawValue
        self.body = body
    }

    init(_ payload: inout MoQTPayload) throws {
        type = try payload.getInt()
        body = try payload.getBytes(limit: 65_535)
    }

    var data: Data {
        var payload = MoQTPayload()
        payload.putInt(type)
        payload.putBytes(body)
        return payload.data
    }
}
