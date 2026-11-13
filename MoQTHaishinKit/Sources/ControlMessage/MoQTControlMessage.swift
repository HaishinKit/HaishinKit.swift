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

public struct MoQTKeyValue: Sendable {
    public enum Value: Sendable {
        case integer(UInt64)
        case bytes(Data)
    }

    public let type: UInt64
    public let value: Value

    static func decode(_ payload: inout MoQTPayload) throws -> [Self] {
        var fields: [Self] = []
        var type: UInt64 = 0
        while payload.bytesAvailable > 0 {
            let (next, overflow) = type.addingReportingOverflow(try payload.getInt())
            guard !overflow else { throw MoQTPayload.Error.invalidField }
            type = next
            let value: Value = type.isMultiple(of: 2)
                ? .integer(try payload.getInt())
                : .bytes(try payload.getBytes(limit: 65_535))
            fields.append(.init(type: type, value: value))
        }
        return fields
    }
}

public struct MoQTSetup: Sendable {
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

public struct MoQTAuthorizationToken: Sendable {
    public let type: UInt64
    public let value: Data

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

public struct MoQTRequestError: Swift.Error {
    public let code: UInt64
    public let retryAfterMilliseconds: UInt64?
    public let reasonPhrase: String
    public let details: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        code = try payload.getInt()
        let interval = try payload.getInt()
        retryAfterMilliseconds = interval == 0 ? nil : interval - 1
        reasonPhrase = String(decoding: try payload.getBytes(limit: 1024), as: UTF8.self)
        details = try MoQTKeyValue.decode(&payload)
    }
}

public struct MoQTRequestOk: Sendable {
    public let expires: UInt64?

    init(_ payload: inout MoQTPayload) throws {
        let parameters = try MoQTResponseParameters(&payload, allowsLargestObject: false)
        guard payload.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
        expires = parameters.expires
    }
}

public struct MoQTSubscribeOk: Sendable {
    public let trackAlias: UInt64
    public let expires: UInt64?
    public let largestGroupId: UInt64?
    public let largestObjectId: UInt64?
    public let trackProperties: [MoQTKeyValue]

    init(_ payload: inout MoQTPayload) throws {
        trackAlias = try payload.getInt()
        let parameters = try MoQTResponseParameters(&payload, allowsLargestObject: true)
        expires = parameters.expires
        largestGroupId = parameters.largestGroupId
        largestObjectId = parameters.largestObjectId
        trackProperties = try MoQTKeyValue.decode(&payload)
    }
}

private struct MoQTResponseParameters {
    var expires: UInt64?
    var largestGroupId: UInt64?
    var largestObjectId: UInt64?

    init(_ payload: inout MoQTPayload, allowsLargestObject: Bool) throws {
        let count = try payload.getInt()
        var type: UInt64 = 0
        for _ in 0..<count {
            let (next, overflow) = type.addingReportingOverflow(try payload.getInt())
            guard !overflow, next > type else { throw MoQTPayload.Error.invalidField }
            type = next
            switch type {
            case 8:
                expires = try payload.getInt()
            case 9 where allowsLargestObject:
                largestGroupId = try payload.getInt()
                largestObjectId = try payload.getInt()
            default:
                throw MoQTPayload.Error.invalidField
            }
        }
    }
}
