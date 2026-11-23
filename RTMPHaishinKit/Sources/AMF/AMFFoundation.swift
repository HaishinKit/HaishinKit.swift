import Foundation

/// The singleton AMFUndefined object.
public let kAMFUndefined = AMFUndefined()

/// The AMFObject typealias represents an object for AcrionScript.
public typealias AMFObject = [String: (any Sendable)?]

/// The AMFUndefined structure represents an undefined for ActionScript.
public struct AMFUndefined: Sendable, CustomStringConvertible {
    public var description: String {
        "undefined"
    }
}

/// The AMFTypedObject structure represents a typed object for ActionScript.
public struct AMFTypedObject: Sendable {
    /// The type name.
    public let typeName: String
    /// The data of object contents.
    public let data: AMFObject
}

// MARK: -
/// The AMFArray structure represents an array value for ActionScript.
public struct AMFArray: Sendable {
    private(set) var data: [(any Sendable)?]
    private(set) var dict: [String: (any Sendable)?] = [:]

    /// The length of an array.
    public var length: Int {
        data.count
    }

    /// Creates a new instance containing the specified number of a single.
    public init(count: Int) {
        self.data = [(any Sendable)?](repeating: kAMFUndefined, count: count)
    }

    /// Creates a new instance of data.
    public init(data: [(any Sendable)?]) {
        self.data = data
    }

    init(_ dict: AMFObject) {
        self.dict = dict
        self.data = .init()
    }
}

extension AMFArray: ExpressibleByArrayLiteral {
    // MARK: ExpressibleByArrayLiteral
    public init (arrayLiteral elements: (any Sendable)?...) {
        self = AMFArray(data: elements)
    }

    /// Accesses the element at the specified position.
    public subscript(i: Any) -> (any Sendable)? {
        get {
            if let i: Int = i as? Int {
                return i < data.count ? data[i] : kAMFUndefined
            }
            if let i: String = i as? String {
                if let value = dict[i] {
                    return value
                }
                if let i = Int(i) {
                    return i < data.count ? data[i] : kAMFUndefined
                }
                return dict[i] as (any Sendable)
            }
            return nil
        }
        set {
            if let i = i as? Int {
                if data.count <= i {
                    data += [(any Sendable)?](repeating: kAMFUndefined, count: i - data.count + 1)
                }
                data[i] = newValue
            }
            if let i = i as? String {
                if let i = Int(i) {
                    if data.count <= i {
                        data += [(any Sendable)?](repeating: kAMFUndefined, count: i - data.count + 1)
                    }
                    data[i] = newValue
                    return
                }
                dict[i] = newValue
            }
        }
    }
}

extension AMFArray: CustomDebugStringConvertible {
    // MARK: CustomDebugStringConvertible
    public var debugDescription: String {
        data.debugDescription + ":" + dict.debugDescription
    }
}

extension AMFArray: Equatable {
    // MARK: Equatable
    public static func == (lhs: AMFArray, rhs: AMFArray) -> Bool {
        (lhs.data.description == rhs.data.description) && (lhs.dict.description == rhs.dict.description)
    }
}

// MARK: -
/// ActionScript 1.0 and 2.0 and flash.xml.XMLDocument in ActionScript 3.0
/// - seealso: 2.17 XML Document Type (amf0-file-format-specification.pdf)
/// - seealso: 3.9 XMLDocument type (amf-file-format-spec.pdf)
public struct AMFXMLDocument: Sendable, CustomStringConvertible {
    public var description: String {
        data
    }

    private let data: String

    /// Creates a new instance of string.
    public init(data: String) {
        self.data = data
    }
}

extension AMFXMLDocument: Equatable {
    // MARK: Equatable
    public static func == (lhs: AMFXMLDocument, rhs: AMFXMLDocument) -> Bool {
        (lhs.description == rhs.description)
    }
}

// MARK: -
/// ActionScript 3.0 introduces a new XML type.
/// - seealso: 3.13 XML type (amf-file-format-spec.pdf)
public struct AMFXML: Sendable, CustomStringConvertible {
    public var description: String {
        data
    }

    private let data: String

    /// Creates a new instance of string.
    public init(data: String) {
        self.data = data
    }
}

extension AMFXML: Equatable {
    // MARK: Equatable
    public static func == (lhs: AMFXML, rhs: AMFXML) -> Bool {
        (lhs.description == rhs.description)
    }
}
