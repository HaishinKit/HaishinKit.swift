import Foundation

/// A factory responsible for creating `ScreenObject` instances
/// from a `ScreenObjectSnapshot`.
///
/// `ScreenObjectFactory` centralizes the logic for instantiating
/// concrete `ScreenObject` subclasses based on the snapshot's
/// logical type. This ensures that object creation is consistent
/// and decoupled from snapshot deserialization logic.
///
/// This factory is isolated to `ScreenActor`, making it safe to use
/// in actor-based concurrency contexts.
@ScreenActor
public struct ScreenObjectFactory {
    /// Creates a new `ScreenObjectFactory` instance.
    ///
    /// This initializer performs no configuration and exists
    /// primarily to allow explicit construction of the factory.
    public init() {
    }

    /// Creates a `ScreenObject` from the given snapshot.
    ///
    /// This method inspects the snapshot's `type` and instantiates
    /// the corresponding concrete `ScreenObject` implementation.
    /// After creation, common properties such as elements, alignment,
    /// and layout margins are applied to the resulting object.
    ///
    /// - Parameter snapshot: A snapshot describing the state and
    ///   configuration of a screen object.
    /// - Returns: A fully configured `ScreenObject` instance if the
    ///   snapshot's type is supported; otherwise, `nil`.
    public func make(_ snapshot: ScreenObjectSnapshot) -> ScreenObject? {
        var screenObject: ScreenObject?
        switch snapshot.type {
        case ImageScreenObject.type:
            screenObject = ImageScreenObject(id: snapshot.id)
        case TextScreenObject.type:
            screenObject = TextScreenObject(id: snapshot.id)
        default:
            break
        }
        screenObject?.elements = snapshot.elements
        screenObject?.horizontalAlignment = .init(rawValue: snapshot.horizontalAlignment) ?? .left
        screenObject?.verticalAlignment = .init(rawValue: snapshot.verticalAlignment) ?? .top
        screenObject?.layoutMargin = .init(
            top: CGFloat(snapshot.layoutMargin.top),
            left: CGFloat(snapshot.layoutMargin.left),
            bottom: CGFloat(snapshot.layoutMargin.bottom),
            right: CGFloat(snapshot.layoutMargin.right)
        )
        return screenObject
    }
}
