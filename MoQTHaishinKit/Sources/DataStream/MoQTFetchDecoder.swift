import Foundation

struct MoQTFetchDecoder {
    var group: UInt64?
    var object: UInt64?
    var subgroup: UInt64?
    var priority: UInt8?

    mutating func decode(_ payload: inout MoQTPayload) throws -> MoQTObject? {
        let flags = try payload.getInt()
        if flags == 0x80 || flags == 0x81 {
            guard group != nil else { throw MoQTPayload.Error.invalidField }
            object = .max
            return nil
        }
        if [0x8c, 0x10c, 0x20c, 0x40c].contains(flags) {
            let groupDelta = try payload.getInt()
            let objectDelta = try payload.getInt()
            let newGroup = try group.map { try add($0, groupDelta) } ?? groupDelta
            let newObject = try group != nil && groupDelta == 0 ? add(add(required(object), objectDelta), 1) : objectDelta
            group = newGroup
            object = newObject
            return nil
        }
        guard flags < 128 else { throw MoQTPayload.Error.invalidField }
        let hasGroup = flags & 8 != 0
        let hasObject = flags & 4 != 0
        let newGroup: UInt64
        if hasGroup {
            let delta = try payload.getInt()
            newGroup = try group.map { try add(add($0, delta), 1) } ?? delta
        } else {
            newGroup = try required(group)
        }
        let newSubgroup: UInt64?
        switch flags & 0x43 {
        case 0: newSubgroup = 0
        case 1: newSubgroup = try required(subgroup)
        case 2: newSubgroup = try add(required(subgroup), 1)
        case 3: newSubgroup = try payload.getInt()
        default: newSubgroup = nil
        }
        let newObject: UInt64
        if hasObject {
            let delta = try payload.getInt()
            newObject = try hasGroup ? delta : add(add(required(object), delta), 2)
        } else {
            guard group != nil else { throw MoQTPayload.Error.invalidField }
            newObject = try add(required(object), 1)
        }
        let newPriority = try flags & 0x10 != 0 ? payload.getByte() : required(priority)
        var properties: [MoQTKeyValue] = []
        if flags & 0x20 != 0 {
            var fields = MoQTPayload(try payload.getBytes())
            properties = try MoQTKeyValue.decode(&fields)
        }
        let data = try payload.getBytes()
        group = newGroup
        object = newObject
        subgroup = newSubgroup
        priority = newPriority
        return MoQTObject(id: newObject, status: nil, data: data, trackAlias: nil,
                          groupId: newGroup, subgroupId: newSubgroup, properties: properties)
    }

    private func required<T>(_ value: T?) throws -> T {
        guard let value else { throw MoQTPayload.Error.invalidField }
        return value
    }

    private func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw MoQTPayload.Error.invalidField }
        return value
    }
}
