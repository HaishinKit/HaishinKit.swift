import Foundation

/// A counted sequence of draft-23 message parameters.
struct MoQTMessageParameters {
    struct Field {
        let type: UInt64
        let value: Data
    }

    let fields: [Field]

    init(_ payload: inout MoQTPayload, allowed: Set<UInt64>, nested: Bool = false) throws {
        let count = try payload.getInt()
        var fields: [Field] = []
        var previous: UInt64 = 0
        for _ in 0..<count {
            let (type, overflow) = previous.addingReportingOverflow(try payload.getInt())
            guard !overflow, allowed.contains(type),
                  type != previous || [3, 0x25, 0x26, 0x27, 0x28, 0x29].contains(type) else {
                throw MoQTPayload.Error.invalidField
            }
            let start = payload.position
            switch type {
            case 2, 4, 6, 8, 0x0a, 0x32, 0x36:
                _ = try payload.getInt()
            case 3, 0x25...0x29:
                _ = try payload.getBytes()
            case 9:
                _ = try payload.getInt()
                _ = try payload.getInt()
            case 0x11, 0x35:
                guard try payload.getByte() <= 1 else { throw MoQTPayload.Error.invalidField }
            case 0x20:
                _ = try payload.getByte()
            case 0x22:
                guard (1...2).contains(try payload.getByte()) else { throw MoQTPayload.Error.invalidField }
            case 0x21:
                let filter = try payload.getInt()
                guard filter <= 5 else { throw MoQTPayload.Error.invalidField }
                let fieldsByFilter = [0, 1, 2, 3, 4, 0]
                for _ in 0..<fieldsByFilter[Int(filter)] { _ = try payload.getInt() }
            case 0x23 where !nested:
                _ = try Self(&payload, allowed: [0x0a, 0x20, 0x21, 0x22, 0x25, 0x26, 0x27, 0x28], nested: true)
            case 0x34:
                _ = try payload.getNamespace()
            default:
                throw MoQTPayload.Error.invalidField
            }
            fields.append(.init(type: type, value: payload.data.subdata(in: start..<payload.position)))
            previous = type
        }
        self.fields = fields
    }

    func encode(into payload: inout MoQTPayload) {
        payload.putInt(UInt64(fields.count))
        var previous: UInt64 = 0
        for field in fields {
            payload.putInt(field.type - previous)
            payload.putData(field.value)
            previous = field.type
        }
    }
}
