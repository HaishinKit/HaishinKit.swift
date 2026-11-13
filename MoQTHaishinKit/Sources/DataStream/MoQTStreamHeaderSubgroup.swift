import Foundation

public struct MoQTStreamHeaderSubgroup: Sendable {
    public let trackAlias: UInt64
    public let groupId: UInt64
    public let subgroupId: UInt64?
    public let publisherPriority: UInt8?
    let hasProperties: Bool

    public var payload: Data {
        var payload = MoQTPayload()
        let subgroupMode: UInt64 = subgroupId == nil ? 0x02 : 0x04
        let priorityFlag: UInt64 = publisherPriority == nil ? 0x20 : 0
        payload.putInt(0x10 | subgroupMode | priorityFlag | (hasProperties ? 1 : 0))
        payload.putInt(trackAlias)
        payload.putInt(groupId)
        if let subgroupId { payload.putInt(subgroupId) }
        if let publisherPriority { payload.putByte(publisherPriority) }
        return payload.data
    }

    public init(trackAlias: UInt64, groupId: UInt64, subgroupId: UInt64, publisherPriority: UInt8) {
        self.trackAlias = trackAlias
        self.groupId = groupId
        self.subgroupId = subgroupId
        self.publisherPriority = publisherPriority
        hasProperties = false
    }

    init(flags: UInt64, payload: inout MoQTPayload) throws {
        guard flags < 128, flags & 0x10 != 0, flags & 0x06 != 0x06 else {
            throw MoQTPayload.Error.invalidField
        }
        trackAlias = try payload.getInt()
        groupId = try payload.getInt()
        switch flags & 0x06 {
        case 0: subgroupId = 0
        case 2: subgroupId = nil
        default: subgroupId = try payload.getInt()
        }
        publisherPriority = flags & 0x20 == 0 ? try payload.getByte() : nil
        hasProperties = flags & 1 != 0
    }
}
