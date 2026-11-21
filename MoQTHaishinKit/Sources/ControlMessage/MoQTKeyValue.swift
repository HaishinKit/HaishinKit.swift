import Foundation

/// A decoded MOQT setup option, error detail, or property.
public struct MoQTKeyValue: Sendable {
    /// The wire value associated with a MOQT field type.
    public enum Value: Sendable {
        /// An unsigned variable-length integer.
        case integer(UInt64)
        /// A length-prefixed byte sequence.
        case bytes(Data)
    }

    /// The field type identifier after applying the wire delta.
    public let type: UInt64
    /// The decoded field value.
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

    static func encode(_ fields: [Self], into payload: inout MoQTPayload) {
        var previous: UInt64 = 0
        for field in fields {
            payload.putInt(field.type - previous)
            switch field.value {
            case .integer(let value): payload.putInt(value)
            case .bytes(let value): payload.putBytes(value)
            }
            previous = field.type
        }
    }
}
