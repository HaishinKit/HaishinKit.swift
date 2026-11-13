import Foundation

/// The header of a unidirectional MOQT subgroup stream.
public struct MoQTStreamHeaderSubgroup: Sendable {
    /// The alias assigned to the track on this session.
    public let trackAlias: UInt64
    /// The group containing the subgroup.
    public let groupId: UInt64
    /// The subgroup identifier, or nil if inferred from the first object.
    public let subgroupId: UInt64?
    /// The publisher priority, or nil if inherited from the track.
    public let publisherPriority: UInt8?
    let hasProperties: Bool

    /// The encoded subgroup header, including its stream type flags.
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

    /// Creates a subgroup header with an explicit identifier and priority.
    ///
    /// - Parameters:
    ///   - trackAlias: The session-specific track alias.
    ///   - groupId: The group containing the subgroup.
    ///   - subgroupId: The subgroup identifier.
    ///   - publisherPriority: The publisher priority, where lower values indicate higher priority.
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
