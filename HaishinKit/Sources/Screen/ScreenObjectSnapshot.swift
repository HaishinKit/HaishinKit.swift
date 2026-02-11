import Foundation

/// A snapshot representation of a screen object.
///
/// `ScreenObjectSnapshot` is an immutable, serializable value type that
/// captures the current state of a screen object hierarchy.
/// It is typically used for state persistence, debugging,
/// inter-process communication, or rendering synchronization.
public struct ScreenObjectSnapshot: Codable, Sendable {
    /// A rectangular region that defines the position and size
    /// of a screen object in screen coordinates.
    public struct Size: Codable, Sendable {
        /// The width of the rectangle.
        public let width: Int
        /// The height of the rectangle.
        public let height: Int

        var cgSize: CGSize {
            return CGSize(width: width, height: height)
        }
    }

    /// A value type that represents inset distances from each edge.
    ///
    /// `EdgeInsets` is typically used to describe padding or margins
    /// around a rectangular area. Each value represents the distance
    /// from the corresponding edge, expressed in logical units.
    ///
    /// This type is immutable, `Codable`, and `Sendable`, making it
    /// suitable for use in value-based layouts, serialization,
    /// and concurrency-safe contexts.
    public struct EdgeInsets: Codable, Sendable {
        /// The inset from the top edge.
        public let top: Int
        /// The inset from the left edge.
        public let left: Int
        /// The inset from the bottom edge.
        public let bottom: Int
        /// The inset from the right edge.
        public let right: Int
    }

    /// Logical type of the screen object.
    ///
    /// This value is typically used for serialization, debugging,
    /// or distinguishing between different kinds of screen objects.
    public let type: String

    /// Unique identifier of the screen object.
    ///
    /// The identifier must be unique within the owning scene or document
    /// and is commonly used for lookup, diffing, and state management.
    public let id: String

    /// The frame of the screen object expressed in screen coordinates.
    public let size: Size

    /// A Boolean value indicating whether the screen object is visible.
    public let isVisible: Bool

    /// The layout margins applied around the content.
    public let layoutMargin: EdgeInsets

    /// The layout margins applied around the content.
    public let horizontalAlignment: Int

    /// Vertical alignment of the screen object.
    ///
    /// The value is typically mapped to a predefined alignment definition
    /// (for example: top, center, bottom).
    public let verticalAlignment: Int

    /// A collection of additional key-value attributes associated
    /// with the screen object.
    ///
    /// This dictionary is commonly used to store implementation-specific
    /// or extensible properties that are not part of the core model.
    public let elements: [String: String]

    /// Child screen object snapshots.
    ///
    /// This property represents the hierarchical structure of screen objects,
    /// allowing nested objects to be captured and reconstructed.
    public let children: [ScreenObjectSnapshot]
}
