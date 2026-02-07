import Accelerate
import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import VideoToolbox

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

@ScreenActor
protocol ScreenObjectConvertible {
    static var type: String { get }
}

extension ScreenObjectConvertible {
    static var type: String { "object" }
}

// The ScreenObject class is the abstract class for all objects that are rendered on the screen.
@ScreenActor
open class ScreenObject: ScreenObjectConvertible {
    /// The horizontal alignment for the screen object.
    public enum HorizontalAlignment: Int, Sendable {
        /// A guide that marks the left edge of the screen object.
        case left = 0
        /// A guide that marks the borizontal center of the screen object.
        case center = 1
        /// A guide that marks the right edge of the screen object.
        case right = 2
    }

    /// The vertical alignment for the screen object.
    public enum VerticalAlignment: Int, Sendable {
        /// A guide that marks the top edge of the screen object.
        case top = 0
        /// A guide that marks the vertical middle of the screen object.
        case middle = 1
        /// A guide that marks the bottom edge of the screen object.
        case bottom = 2
    }

    enum BlendMode {
        case normal
        case alpha
    }

    /// The screen object container that contains this screen object
    public internal(set) weak var parent: ScreenObjectContainer?

    /// Specifies the size rectangle.
    public var size: CGSize = .zero {
        didSet {
            guard size != oldValue else {
                return
            }
            shouldInvalidateLayout = true
        }
    }

    /// Unique identifier of this screen object.
    ///
    /// The identifier must be unique within the owning scene or document
    /// and is commonly used for lookup and state management.
    public let id: String

    /// The bounds rectangle.
    public internal(set) var bounds: CGRect = .zero

    /// Specifies the visibility of the object.
    public var isVisible = true

    #if os(macOS)
    /// Specifies the default spacing to laying out content in the screen object.
    public var layoutMargin: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    #else
    /// Specifies the default spacing to laying out content in the screen object.
    public var layoutMargin: UIEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    #endif

    /// Specifies the radius to use when drawing rounded corners.
    public var cornerRadius: CGFloat = 0.0

    /// Specifies the alignment position along the vertical axis.
    public var verticalAlignment: VerticalAlignment = .top

    /// Specifies the alignment position along the horizontal axis.
    public var horizontalAlignment: HorizontalAlignment = .left

    public var elements: [String: String] {
        get {
            return [:]
        }
        set(value) {
        }
    }

    var blendMode: BlendMode {
        .alpha
    }

    var shouldInvalidateLayout = true

    /// Creates a screen object.
    public init(id: String? = nil) {
        self.id = id ?? UUID().uuidString
    }

    /// Invalidates the current layout and triggers a layout update.
    public func invalidateLayout() {
        shouldInvalidateLayout = true
    }

    /// Makes ciImage for offscreen image.
    open func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        return nil
    }

    /// Finds a screen object with the specified identifier.
    ///
    /// This method compares the given identifier with the receiver’s identifier
    /// and returns the receiver itself if they match.
    /// Subclasses may override this method to provide recursive or
    /// hierarchical lookup behavior.
    ///
    /// - Parameter id: The unique identifier of the screen object to find.
    /// - Returns: The screen object whose identifier matches the given value,
    ///   or `nil` if no match is found.
    open func findById(_ id: String) -> ScreenObject? {
        if self.id == id {
            return self
        }
        return nil
    }

    /// Makes screen object bounds for offscreen image.
    open func makeBounds(_ size: CGSize) -> CGRect {
        guard let parent else {
            return .init(origin: .zero, size: self.size)
        }

        let width = size.width == 0 ? max(parent.bounds.width - layoutMargin.left - layoutMargin.right + size.width, 0) : size.width
        let height = size.height == 0 ? max(parent.bounds.height - layoutMargin.top - layoutMargin.bottom + size.height, 0) : size.height

        let parentX = parent.bounds.origin.x
        let parentWidth = parent.bounds.width
        let x: CGFloat
        switch horizontalAlignment {
        case .center:
            x = parentX + (parentWidth - width) / 2
        case .left:
            x = parentX + layoutMargin.left
        case .right:
            x = parentX + (parentWidth - width) - layoutMargin.right
        }

        let parentY = parent.bounds.origin.y
        let parentHeight = parent.bounds.height
        let y: CGFloat
        switch verticalAlignment {
        case .top:
            y = parentY + layoutMargin.top
        case .middle:
            y = parentY + (parentHeight - height) / 2
        case .bottom:
            y = parentY + (parentHeight - height) - layoutMargin.bottom
        }

        return .init(x: x, y: y, width: width, height: height)
    }

    func layout(_ renderer: some ScreenRenderer) {
        bounds = makeBounds(size)
        renderer.layout(self)
        shouldInvalidateLayout = false
    }

    func draw(_ renderer: some ScreenRenderer) {
        renderer.draw(self)
    }
}

extension ScreenObject: Hashable {
    // MARK: Hashable
    nonisolated public static func == (lhs: ScreenObject, rhs: ScreenObject) -> Bool {
        lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
