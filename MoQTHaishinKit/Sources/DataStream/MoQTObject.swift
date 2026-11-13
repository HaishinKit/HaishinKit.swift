import Foundation

/// A MOQT object and its available delivery metadata.
public struct MoQTObject: Sendable {
    /// The object identifier within its group.
    public let id: UInt64
    /// The explicit wire status, or nil when the wire format implies normal status.
    public let status: UInt64?
    /// The object payload bytes.
    public let data: Data
    /// The track alias for a received object.
    public let trackAlias: UInt64?
    /// The group identifier for a received object.
    public let groupId: UInt64?
    /// The subgroup identifier for a received subgroup object.
    public let subgroupId: UInt64?
    /// The properties supplied by the peer for this object.
    public let properties: [MoQTKeyValue]

    /// Creates an object to send with a subgroup header.
    ///
    /// - Parameters:
    ///   - id: The object identifier within its group.
    ///   - status: An optional explicit wire status for an empty payload.
    ///   - data: The object payload bytes.
    public init(id: UInt64, status: UInt64?, data: Data) {
        self.init(id: id, status: status, data: data, trackAlias: nil, groupId: nil, subgroupId: nil, properties: [])
    }

    private init(id: UInt64, status: UInt64?, data: Data, trackAlias: UInt64?, groupId: UInt64?,
                 subgroupId: UInt64?, properties: [MoQTKeyValue]) {
        self.id = id
        self.status = status
        self.data = data
        self.trackAlias = trackAlias
        self.groupId = groupId
        self.subgroupId = subgroupId
        self.properties = properties
    }

    func encode(after previous: UInt64?, into payload: inout MoQTPayload) throws {
        guard previous.map({ id > $0 }) ?? true, status == nil || (data.isEmpty && [0, 3, 4].contains(status)) else {
            throw MoQTPayload.Error.invalidField
        }
        payload.putInt(previous.map { id - $0 - 1 } ?? id)
        payload.putInt(UInt64(data.count))
        if data.isEmpty { payload.putInt(status ?? 0) }
        payload.putData(data)
    }

    static func readSubgroup(_ payload: inout MoQTPayload, header: MoQTStreamHeaderSubgroup,
                             previous: UInt64?, subgroupId: UInt64?) throws -> Self {
        let delta = try payload.getInt()
        let id: UInt64
        if let previous {
            let (sum, overflow) = previous.addingReportingOverflow(delta)
            guard !overflow, sum < UInt64.max else { throw MoQTPayload.Error.invalidField }
            id = sum + 1
        } else {
            id = delta
        }
        let properties = header.hasProperties ? try readProperties(&payload) : []
        let length = try payload.getInt()
        let status = length == 0 ? try payload.getInt() : nil
        guard status == nil || ([0, 3, 4].contains(status) && (status == 0 || properties.isEmpty)) else {
            throw MoQTPayload.Error.invalidField
        }
        return .init(id: id, status: status, data: try payload.getData(length), trackAlias: header.trackAlias,
                     groupId: header.groupId, subgroupId: subgroupId ?? header.subgroupId ?? id, properties: properties)
    }

    static func readDatagram(_ payload: inout MoQTPayload) throws -> Self? {
        let flags = try payload.getInt()
        if flags == 0x132b3e29 { return nil }
        guard flags & ~0x2f == 0, flags & 0x22 != 0x22 else { throw MoQTPayload.Error.invalidField }
        let trackAlias = try payload.getInt()
        let groupId = try payload.getInt()
        let id = flags & 4 == 0 ? try payload.getInt() : 0
        if flags & 8 == 0 { _ = try payload.getByte() }
        let properties = flags & 1 != 0 ? try readProperties(&payload) : []
        let status = flags & 0x20 != 0 ? try payload.getInt() : nil
        guard flags & 1 == 0 || !properties.isEmpty,
              status == nil || ([0, 3, 4].contains(status) && (status == 0 || (properties.isEmpty && payload.bytesAvailable == 0))) else {
            throw MoQTPayload.Error.invalidField
        }
        return .init(id: id, status: status, data: payload.remainder(), trackAlias: trackAlias, groupId: groupId,
                     subgroupId: nil, properties: properties)
    }

    private static func readProperties(_ payload: inout MoQTPayload) throws -> [MoQTKeyValue] {
        var fields = MoQTPayload(try payload.getBytes())
        return try MoQTKeyValue.decode(&fields)
    }
}
