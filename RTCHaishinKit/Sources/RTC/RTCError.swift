/// An error reported by the libdatachannel C API.
public enum RTCError: RawRepresentable, Swift.Error {
    @discardableResult
    static func check(_ result: Int32) throws -> Int32 {
        if result < 0 {
            throw RTCError(rawValue: result)
        }
        return result
    }

    /// The underlying library result code.
    public typealias RawValue = Int32

    /// An argument is invalid.
    case invalid
    /// The operation failed at runtime.
    case failure
    /// The requested element is unavailable.
    case notAvail
    /// The supplied buffer is too small.
    case tooSmall
    /// A result code without a named case in this enumeration.
    case undefined(value: Int32)

    /// The corresponding libdatachannel result code.
    public var rawValue: Int32 {
        switch self {
        case .invalid:
            return -1
        case .failure:
            return -2
        case .notAvail:
            return -3
        case .tooSmall:
            return -4
        case .undefined(let value):
            return value
        }
    }

    /// Creates an error from a library result code.
    ///
    /// Codes other than `-1` through `-4` are preserved in `undefined(value:)`.
    ///
    /// - Parameter rawValue: The result code to represent.
    public init(rawValue: Int32) {
        switch rawValue {
        case -1:
            self = .invalid
        case -2:
            self = .failure
        case -3:
            self = .notAvail
        case -4:
            self = .tooSmall
        default:
            self = .undefined(value: rawValue)
        }
    }
}
