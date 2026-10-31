import Foundation
import libsrt

/// An SRT socket option paired with a value encoded for the underlying library.
public struct SRTSocketOption: Sendable {
    /// Errors that can occur when converting, reading, or applying an option.
    public enum Error: Swift.Error {
        /// The option is invalid or the SRT library rejected the operation.
        case invalidOption(_ message: String)
        /// The value cannot be converted to the option’s underlying type.
        case invalidArgument(_ message: String)
    }

    private static let trueStringLiterals: [String: Bool] = [
        "1": true,
        "on": true,
        "yes": true,
        "true": true
    ]

    private static let falseStringLiterals: [String: Bool] = [
        "0": false,
        "off": false,
        "no": false,
        "false": false
    ]

    /// The underlying value type of an SRT socket option.
    public enum CType: Int, Sendable {
        /// A UTF-8 string.
        case string
        /// A signed 32-bit integer.
        case int32
        /// A signed 64-bit integer.
        case int64
        /// A Boolean value.
        case bool

        var size: Int {
            switch self {
            case .string:
                return 512
            case .int32:
                return MemoryLayout<Int32>.size
            case .int64:
                return MemoryLayout<Int64>.size
            case .bool:
                return MemoryLayout<Bool>.size
            }
        }

        func data(_ value: any Sendable) throws -> Data {
            switch self {
            case .string:
                guard let data = String(describing: value).data(using: .utf8) else {
                    throw Error.invalidArgument("\(value)")
                }
                return data
            case .bool:
                guard var value = value as? Bool else {
                    throw Error.invalidArgument("\(value)")
                }
                return .init(bytes: &value, count: size)
            case .int32:
                guard var value = value as? Int32 else {
                    throw Error.invalidArgument("\(value)")
                }
                return .init(bytes: &value, count: size)
            case .int64:
                guard var value = value as? Int64 else {
                    throw Error.invalidArgument("\(value)")
                }
                return .init(bytes: &value, count: size)
            }
        }
    }

    /// The stage at which an SRT socket option can be configured.
    public enum Restriction: Int, Sendable {
        /// The option must be applied before the socket is bound.
        case preBind
        /// The option is configured before a connection is established.
        case pre
        /// The option can be configured after a connection is established.
        case post
    }

    /// The name, underlying type, and configuration restriction of an SRT socket option.
    public struct Name: Sendable {
        /// The string representation of an option name.
        public typealias RawValue = String

        /// The option name used in URL query parameters.
        public let rawValue: String
        let symbol: SRT_SOCKOPT
        let restriction: Restriction?
        let type: CType

        /// Creates a socket option descriptor.
        ///
        /// - Parameters:
        ///   - rawValue: The option’s string name.
        ///   - symbol: The corresponding SRT library constant.
        ///   - restriction: When the option may be configured, or `nil` for no writable stage.
        ///   - type: The type used to encode and decode values.
        public init(rawValue: String, symbol: SRT_SOCKOPT, restriction: Restriction?, type: CType) {
            self.rawValue = rawValue
            self.symbol = symbol
            self.restriction = restriction
            self.type = type
        }
    }

    /// The socket option's name.
    public let name: Name

    /// The option value formatted as a string.
    public var stringValue: String {
        switch name.type {
        case .string:
            return String(data: data, encoding: .utf8) ?? ""
        case .int32:
            return data.withUnsafeBytes { $0.load(as: Int32.self) }.description
        case .int64:
            return data.withUnsafeBytes { $0.load(as: Int64.self) }.description
        case .bool:
            return (data[0] == 1).description
        }
    }

    /// The option value as an integer, or `-1` for a string option.
    ///
    /// Boolean values are represented as `0` or `1`.
    public var intValue: Int {
        switch name.type {
        case .string:
            return -1
        case .int32:
            return Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
        case .int64:
            return Int(data.withUnsafeBytes { $0.load(as: Int64.self) })
        case .bool:
            return Int(data[0])
        }
    }

    /// The option value interpreted as a Boolean.
    ///
    /// Integer values are `true` only when equal to `1`. String options return `false`.
    public var boolValue: Bool {
        switch name.type {
        case .string:
            return false
        case .int32:
            return Int(data.withUnsafeBytes { $0.load(as: Int32.self) }) == 1
        case .int64:
            return Int(data.withUnsafeBytes { $0.load(as: Int64.self) }) == 1
        case .bool:
            return data[0] == 1
        }
    }

    private let data: Data

    /// Creates an option by parsing a string.
    ///
    /// Boolean options accept `1`, `on`, `yes`, and `true`, or `0`, `off`, `no`, and
    /// `false`, ignoring case. The transmission type option accepts `live` or `file`.
    ///
    /// - Parameters:
    ///   - name: The option descriptor.
    ///   - value: The value to parse.
    /// - Throws: `Error.invalidOption` or `Error.invalidArgument` if conversion fails.
    public init(name: Name, value: String) throws {
        self.name = name
        switch name.type {
        case .string:
            self.data = try name.type.data(value)
        case .int32:
            switch name.rawValue {
            case "transtype":
                switch value {
                case "live":
                    self.data = try name.type.data(Int32(SRTT_LIVE.rawValue))
                case "file":
                    self.data = try name.type.data(Int32(SRTT_FILE.rawValue))
                default:
                    throw Error.invalidOption(name.rawValue)
                }
            default:
                self.data = try name.type.data(Int32(value))
            }
        case .int64:
            self.data = try name.type.data(Int64(value))
        case .bool:
            let key = String(describing: value).lowercased()
            if let bool = Self.trueStringLiterals[key] {
                self.data = try name.type.data(bool)
            } else if let bool = Self.falseStringLiterals[key] {
                self.data = try name.type.data(bool)
            } else {
                throw Error.invalidOption(name.rawValue)
            }
        }
    }

    /// Creates an option from an integer.
    ///
    /// For Boolean options, only `1` becomes `true`. String options use the decimal
    /// representation. The value must fit the option’s underlying integer type.
    ///
    /// - Parameters:
    ///   - name: The option descriptor.
    ///   - value: The value to encode.
    public init(name: Name, value: Int) throws {
        self.name = name
        switch name.type {
        case .string:
            self.data = try name.type.data(value.description)
        case .int32:
            self.data = try name.type.data(Int32(value))
        case .int64:
            self.data = try name.type.data(Int64(value))
        case .bool:
            self.data = try name.type.data(value == 1)
        }
    }

    init(name: Name, socket: SRTSOCKET) throws {
        self.name = name
        var data = Data(repeating: 0, count: name.type.size)
        var length = Int32(name.type.size)
        let result: Int32 = data.withUnsafeMutableBytes {
            guard let buffer = $0.baseAddress else {
                return -1
            }
            return srt_getsockflag(socket, name.symbol, buffer, &length)
        }
        if result < 0 {
            throw Error.invalidOption(String(cString: srt_getlasterror_str()))
        }
        self.data = data.subdata(in: 0..<Data.Index(length))
    }

    func setSockflag(_ socket: SRTSOCKET) throws {
        let result: Int32 = data.withUnsafeBytes { pointer in
            guard let buffer = pointer.baseAddress else {
                return -1
            }
            return srt_setsockflag(socket, name.symbol, buffer, Int32(data.count))
        }
        if result < 0 {
            throw Error.invalidOption(String(cString: srt_getlasterror_str()))
        }
    }
}
