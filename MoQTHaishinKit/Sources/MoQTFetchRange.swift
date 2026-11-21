/// An inclusive range of group and object identifiers for a FETCH.
public struct MoQTFetchRange: Sendable {
    /// The first group to fetch.
    public let startGroup: UInt64
    /// The first object to fetch in the starting group.
    public let startObject: UInt64
    /// The last group to fetch.
    public let endGroup: UInt64
    /// The last object to fetch in the ending group.
    public let endObject: UInt64

    /// Creates an inclusive range. The fetch rejects a range whose end precedes its start.
    public init(startGroup: UInt64, startObject: UInt64, endGroup: UInt64, endObject: UInt64) {
        self.startGroup = startGroup
        self.startObject = startObject
        self.endGroup = endGroup
        self.endObject = endObject
    }

    func encode(into payload: inout MoQTPayload) throws {
        guard (startGroup, startObject) <= (endGroup, endObject) else { throw MoQTPayload.Error.invalidField }
        payload.putInt(4) // Absolute Range
        payload.putInt(startGroup)
        payload.putInt(startObject)
        payload.putInt(endGroup - startGroup)
        payload.putInt(endObject)
    }
}
