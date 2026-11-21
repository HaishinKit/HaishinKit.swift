struct MoQTResponseParameters {
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
